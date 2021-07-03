/*
 * Author: doe300
 *
 * See the file "LICENSE" for the full license governing this code.
 */

#include "Profiler.h"

#include "log.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <set>
#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#include <unordered_map>

#ifdef MULTI_THREADED
#include <mutex>
#endif

// LCOV_EXCL_START

using namespace vc4c;

using Clock = std::chrono::system_clock;
using Duration = std::chrono::microseconds;

struct profiler::Entry
{
    std::string name;
    std::atomic<Duration ::rep> duration;
    std::atomic_uint64_t invocations;
    std::string fileName;
    std::size_t lineNumber;

    Entry() = default;
    Entry(const Entry&) = delete;
    Entry(Entry&& other) noexcept :
        name(std::move(other.name)), duration(other.duration.load()), invocations(other.invocations.load()),
        fileName(std::move(other.fileName)), lineNumber(other.lineNumber)
    {
    }
    ~Entry() noexcept = default;

    Entry& operator=(const Entry&) = delete;
    Entry& operator=(Entry&& other) noexcept
    {
        if(&other != this)
        {
            name = std::move(other.name);
            duration = other.duration.load();
            invocations = other.invocations.load();
            fileName = std::move(other.fileName);
            lineNumber = other.lineNumber;
        }
        return *this;
    }

    bool operator<(const Entry& right) const noexcept
    {
        if(duration.load() == right.duration.load())
            return name > right.name;
        return duration.load() > right.duration.load();
    }
};

struct profiler::Counter
{
    std::string name;
    std::atomic_uint64_t count;
    std::size_t index;
    std::atomic_uint64_t invocations;
    std::size_t prevCounter;
    std::string fileName;
    std::size_t lineNumber;

    Counter() = default;
    Counter(const Counter&) = delete;
    Counter(Counter&& other) noexcept :
        name(std::move(other.name)), count(other.count.load()), index(other.index),
        invocations(other.invocations.load()), prevCounter(other.prevCounter), fileName(std::move(other.fileName)),
        lineNumber(other.lineNumber)
    {
    }
    ~Counter() noexcept = default;

    Counter& operator=(const Counter&) = delete;
    Counter& operator=(Counter&& other) noexcept
    {
        if(&other != this)
        {
            name = std::move(other.name);
            count = other.count.load();
            index = other.index;
            invocations = other.invocations.load();
            prevCounter = other.prevCounter;
            fileName = std::move(other.fileName);
            lineNumber = other.lineNumber;
        }
        return *this;
    }

    bool operator<(const Counter& right) const noexcept
    {
        if(index == right.index)
            return name > right.name;
        return index < right.index;
    }
};

static std::unordered_map<profiler::HashKey, profiler::Entry> times;
static std::map<std::size_t, profiler::Counter> counters;
#ifdef MULTI_THREADED
static std::mutex lockTimes;
static std::mutex lockCounters;

/**
 * Utility class to cache the profile result thread-locally to be written back at once at thread exit.
 *
 * This reduces the amount of profile result mutex locks required.
 */
struct ThreadResultCache
{
    ~ThreadResultCache()
    {
        // flush all thread-local data to the global data
        if(!localTimes.empty())
        {
            std::lock_guard<std::mutex> guard(lockTimes);
            for(auto& entry : localTimes)
            {
                auto it = times.find(entry.first);
                if(it != times.end())
                {
                    it->second.duration += entry.second.duration;
                    it->second.invocations += entry.second.invocations;
                }
                else
                    times.emplace(entry.first, std::move(entry.second));
            }
        }

        if(!localCounters.empty())
        {
            std::lock_guard<std::mutex> guard(lockCounters);
            for(auto& entry : localCounters)
            {
                auto it = counters.find(entry.first);
                if(it != counters.end())
                {
                    it->second.count += entry.second.count;
                    it->second.invocations += entry.second.invocations;
                }
                else
                    counters.emplace(entry.first, std::move(entry.second));
            }
        }
    }

    std::unordered_map<profiler::HashKey, profiler::Entry> localTimes;
    std::map<std::size_t, profiler::Counter> localCounters;
};

static thread_local std::unique_ptr<ThreadResultCache> threadCache;
#endif

profiler::Entry* profiler::createEntry(HashKey key, std::string name, std::string fileName, std::size_t lineNumber)
{
#ifdef MULTI_THREADED
    if(threadCache)
    {
        auto& entry = threadCache->localTimes[key];
        entry.name = std::move(name);
        entry.fileName = std::move(fileName);
        entry.lineNumber = lineNumber;
        return &entry;
    }
    std::lock_guard<std::mutex> guard(lockTimes);
#endif
    auto& entry = times[key];
    entry.name = std::move(name);
    entry.fileName = std::move(fileName);
    entry.lineNumber = lineNumber;
    return &entry;
}

void profiler::endFunctionCall(Entry* entry, Clock::time_point startTime)
{
    entry->duration += std::chrono::duration_cast<Duration>(Clock::now() - startTime).count();
    ++entry->invocations;
}

static void printResourceUsage(bool writeAsWarning)
{
    auto logFunc = writeAsWarning ? logging::warn : logging::info;
    static const auto pageSizeInKb = static_cast<uint64_t>(sysconf(_SC_PAGESIZE)) / 1024;

    CPPLOG_LAZY_BLOCK(writeAsWarning ? logging::Level::WARNING : logging::Level::DEBUG, {
        rusage usage{};
        if(getrusage(RUSAGE_SELF, &usage) < 0)
        {
            logging::warn() << "Error gathering resource usage: " << strerror(errno) << logging::endl;
            return;
        }
        uint64_t virtualSize = 0;
        uint64_t residentSize = 0;
        uint64_t sharedSize = 0;
        {
            // htop uses this one, see https://github.com/hishamhm/htop/blob/master/linux/LinuxProcessList.c#L480
            std::ifstream fis{"/proc/self/statm"};
            fis >> virtualSize;
            fis >> residentSize;
            fis >> sharedSize;
            if(!fis)
            {
                logging::warn() << "Error reading memory usage: " << strerror(errno) << logging::endl;
                return;
            }
            // next ones are text segment, library (loaded *.so files) and data segment (incl. stack)
        }
        logFunc() << "Resource usage: " << logging::endl;
        logFunc() << "\tCPU time (user):   " << std::setfill(L' ') << std::setw(3) << usage.ru_utime.tv_sec << '.'
                  << std::setfill(L'0') << std::setw(6) << usage.ru_utime.tv_usec << " s" << logging::endl;
        logFunc() << "\tCPU time (kernel): " << std::setfill(L' ') << std::setw(3) << usage.ru_stime.tv_sec << '.'
                  << std::setfill(L'0') << std::setw(6) << usage.ru_stime.tv_usec << " s" << logging::endl;
        logFunc() << "\tVirtual RAM usage: " << std::setfill(L' ') << std::setw(6) << (virtualSize * pageSizeInKb)
                  << " kB" << logging::endl;
        logFunc() << "\tCurrent RAM usage: " << std::setfill(L' ') << std::setw(6) << (residentSize * pageSizeInKb)
                  << " kB" << logging::endl;
        logFunc() << "\tShared RAM usage:  " << std::setfill(L' ') << std::setw(6) << (sharedSize * pageSizeInKb)
                  << " kB" << logging::endl;
        logFunc() << "\tPeek RAM usage:    " << std::setfill(L' ') << std::setw(6) << usage.ru_maxrss << " kB"
                  << logging::endl;
        logFunc() << "\tPage faults (minor/major): " << usage.ru_minflt << '/' << usage.ru_majflt << logging::endl;
    });

    CPPLOG_LAZY_BLOCK(writeAsWarning ? logging::Level::WARNING : logging::Level::DEBUG, {
        std::ifstream fis{"/proc/meminfo"};
        std::string line;
        if(std::getline(fis, line))
            // first line is: MemTotal
            logFunc() << line << logging::endl;
        if(std::getline(fis, line) && std::getline(fis, line))
            // third line is: MemAvailable (free + file cache + buffers) -> everything which could be requested
            logFunc() << line << logging::endl;
    });
}

template <typename T>
struct SortPointerTarget
{
    bool operator()(const T* one, const T* other) const noexcept
    {
        return *one < *other;
    }
};

void profiler::dumpProfileResults(bool writeAsWarning)
{
    logging::logLazy(writeAsWarning ? logging::Level::WARNING : logging::Level::DEBUG, [&]() {
#ifdef MULTI_THREADED
        std::unique_lock<std::mutex> timesGuard(lockTimes, std::defer_lock);
        std::unique_lock<std::mutex> countersGuard(lockCounters, std::defer_lock);
        std::lock(timesGuard, countersGuard);
#endif
        std::set<const Entry*, SortPointerTarget<const Entry>> entries;
        std::set<const Counter*, SortPointerTarget<const Counter>> counts;
        for(auto& entry : times)
        {
            entry.second.name = entry.second.name;
            entries.emplace(&entry.second);
        }
        for(const auto& count : counters)
        {
            counts.emplace(&count.second);
        }

        auto logFunc = writeAsWarning ? logging::warn : logging::info;

        logFunc() << std::setfill(L' ') << logging::endl;
        logFunc() << "Profiling results for " << entries.size() << " functions:" << logging::endl;
        for(const Entry* entry : entries)
        {
            logFunc() << std::setw(40) << entry->name << std::setw(7)
                      << std::chrono::duration_cast<std::chrono::milliseconds>(Duration{entry->duration}).count()
                      << " ms" << std::setw(12) << entry->duration << " us" << std::setw(10) << entry->invocations
                      << " calls" << std::setw(12)
                      << static_cast<uint64_t>(entry->duration) / std::max(entry->invocations.load(), uint64_t{1})
                      << " us/call" << std::setw(64) << entry->fileName << "#" << entry->lineNumber << logging::endl;
        }

        logFunc() << logging::endl;
        logFunc() << "Profiling results for " << counts.size() << " counters:" << logging::endl;
        for(const Counter* counter : counts)
        {
            auto prevCount =
                counter->prevCounter == SIZE_MAX ? 0 : static_cast<int64_t>(counters[counter->prevCounter].count);
            logFunc() << std::setw(40) << counter->name << std::setw(7) << counter->count << " counts" << std::setw(5)
                      << counter->invocations << " calls" << std::setw(6)
                      << counter->count / std::max(counter->invocations.load(), uint64_t{1}) << " avg./call"
                      << std::setw(8) << (counter->prevCounter == SIZE_MAX ? "" : "diff") << std::setw(7)
                      << std::showpos
                      << (counter->prevCounter == SIZE_MAX ? 0 : static_cast<int64_t>(counter->count) - prevCount)
                      << " (" << std::setw(5) << std::showpos
                      << (counter->prevCounter == SIZE_MAX ?
                                 0 :
                                 static_cast<int>(100 *
                                     (-1.0 + static_cast<double>(counter->count) / static_cast<double>(prevCount))))
                      << std::noshowpos << "%)" << std::setw(64) << counter->fileName << "#" << counter->lineNumber
                      << logging::endl;
        }
    });
    times.clear();
    counters.clear();
    printResourceUsage(writeAsWarning);
}

profiler::Counter* profiler::createCounter(
    std::size_t index, std::string name, std::string file, std::size_t line, std::size_t prevIndex)
{
#ifdef MULTI_THREADED
    if(threadCache)
    {
        auto& entry = threadCache->localCounters[index];
        entry.index = index;
        entry.name = std::move(name);
        entry.prevCounter = prevIndex;
        entry.fileName = std::move(file);
        entry.lineNumber = line;
        return &entry;
    }
    std::lock_guard<std::mutex> guard(lockCounters);
#endif
    auto& entry = counters[index];
    entry.index = index;
    entry.name = std::move(name);
    entry.prevCounter = prevIndex;
    entry.fileName = std::move(file);
    entry.lineNumber = line;
    return &entry;
}

void profiler::increaseCounter(Counter* counter, std::size_t value)
{
    counter->count += value;
    ++counter->invocations;
}

void profiler::startThreadCache()
{
#ifdef MULTI_THREADED
    threadCache = std::make_unique<ThreadResultCache>();
#endif
}

void profiler::flushThreadCache()
{
#ifdef MULTI_THREADED
    PROFILE_START(FlushProfileThreadCache);
    threadCache.reset();
    PROFILE_END(FlushProfileThreadCache);
#endif
}

// LCOV_EXCL_STOP
