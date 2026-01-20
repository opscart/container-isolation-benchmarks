/*
 * getpid_bench.c
 * 
 * Minimal benchmark to measure getpid() syscall overhead
 * 
 * Compiled as static binary so it can run in minimal containers (Alpine)
 * Uses direct syscall() to avoid libc wrapper overhead
 */

#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <stdio.h>
#include <time.h>

#define ITERATIONS 10000000  // 10 million iterations
#define WARMUP 1000          // Warmup iterations to stabilize CPU

int main() {
    struct timespec start, end;
    long long diff_ns;
    
    // Warmup: let CPU stabilize, caches warm up
    for (int i = 0; i < WARMUP; i++) {
        syscall(SYS_getpid);
    }
    
    // Actual measurement
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    for (int i = 0; i < ITERATIONS; i++) {
        syscall(SYS_getpid);
    }
    
    clock_gettime(CLOCK_MONOTONIC, &end);
    
    // Calculate elapsed time
    diff_ns = (end.tv_sec - start.tv_sec) * 1000000000LL + 
              (end.tv_nsec - start.tv_nsec);
    
    // Output results
    printf("=== getpid() Syscall Benchmark ===\n");
    printf("Iterations: %d\n", ITERATIONS);
    printf("Total time: %.2f seconds\n", diff_ns / 1000000000.0);
    printf("Average: %.2f nanoseconds per syscall\n", (double)diff_ns / ITERATIONS);
    printf("Rate: %.2f million syscalls/second\n", 
           (ITERATIONS / 1000000.0) / (diff_ns / 1000000000.0));
    
    return 0;
}