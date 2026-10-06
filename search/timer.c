#ifdef _WIN32
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#endif

#include "search_internal.h"

enum { NANOSECONDS_PER_SECOND = 1000000000 };

uint64_t search_now_nanoseconds(void)
{
#ifdef _WIN32
    LARGE_INTEGER counter, frequency;
    uint64_t ticks, ticks_per_second;
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&frequency);
    ticks = (uint64_t) counter.QuadPart;
    ticks_per_second = (uint64_t) frequency.QuadPart;
    return ticks / ticks_per_second * NANOSECONDS_PER_SECOND +
           ticks % ticks_per_second * NANOSECONDS_PER_SECOND /
               ticks_per_second;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t) now.tv_sec * NANOSECONDS_PER_SECOND +
           (uint64_t) now.tv_nsec;
#endif
}
