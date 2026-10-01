#ifdef _WIN32
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#endif

#include "search_internal.h"

double search_now_seconds(void)
{
#ifdef _WIN32
    LARGE_INTEGER counter, frequency;
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&frequency);
    return (double) counter.QuadPart / (double) frequency.QuadPart;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double) now.tv_sec + (double) now.tv_nsec / 1000000000.0;
#endif
}
