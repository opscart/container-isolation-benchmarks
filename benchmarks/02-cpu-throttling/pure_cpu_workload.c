// pure_cpu_workload.c
// Pure CPU workload for throttling benchmark
// No syscalls during busy periods - just computation

#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Get current time in nanoseconds
static inline long long get_time_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

// Pure CPU busy wait - no syscalls during the busy period
void busy_wait_ns(long long ns) {
    long long start = get_time_ns();
    long long end = start + ns;
    long long now;
    
    // Pure computation loop - no syscalls
    volatile long counter = 0;
    do {
        // Do actual work to keep CPU busy
        for (int i = 0; i < 1000; i++) {
            counter += i * i;
        }
        // Only check time occasionally to minimize syscall overhead
        now = get_time_ns();
    } while (now < end);
}

int main(int argc, char *argv[]) {
    // Default: 50ms burst + 50ms sleep for 60 seconds
    int burst_ms = 50;
    int sleep_ms = 50;
    int duration_sec = 60;
    
    if (argc > 1) burst_ms = atoi(argv[1]);
    if (argc > 2) sleep_ms = atoi(argv[2]);
    if (argc > 3) duration_sec = atoi(argv[3]);
    
    printf("Pure CPU Workload Starting\n");
    printf("  Burst: %dms CPU\n", burst_ms);
    printf("  Sleep: %dms idle\n", sleep_ms);
    printf("  Duration: %d seconds\n", duration_sec);
    printf("  Pattern: Minimal syscall overhead for accurate measurement\n");
    fflush(stdout);
    
    long long burst_ns = (long long)burst_ms * 1000000LL;
    long long sleep_ns = (long long)sleep_ms * 1000000LL;
    long long total_ns = (long long)duration_sec * 1000000000LL;
    
    long long start_time = get_time_ns();
    int iterations = 0;
    
    while (get_time_ns() - start_time < total_ns) {
        // CPU burst period - pure computation
        busy_wait_ns(burst_ns);
        
        // Sleep period - actually sleep
        struct timespec sleep_time = {
            .tv_sec = sleep_ms / 1000,
            .tv_nsec = (sleep_ms % 1000) * 1000000
        };
        nanosleep(&sleep_time, NULL);
        
        iterations++;
    }
    
    long long end_time = get_time_ns();
    double actual_duration = (end_time - start_time) / 1e9;
    
    printf("\nWorkload Complete\n");
    printf("  Iterations: %d\n", iterations);
    printf("  Actual duration: %.2f seconds\n", actual_duration);
    printf("  Expected duty cycle: %.1f%%\n", 
           (100.0 * burst_ms) / (burst_ms + sleep_ms));
    
    return 0;
}