#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <unistd.h>

int main(int argc, char **argv) {
    const char *mode = getenv("LENS_FIXTURE_MODE");
    if (!mode) mode = "text";
    int probe = argc == 2;
    if (probe && strcmp(mode, "probe_child") && strcmp(mode, "probe_timeout")) {
        puts("fixture 1"); return 0;
    }
    if (!strcmp(mode, "cpu")) { for (;;) {} }
    if (!strcmp(mode, "memory")) {
        void *memory = malloc(600UL * 1024 * 1024);
        return memory ? 0 : 1;
    }
    if (!strcmp(mode, "limits")) {
        struct rlimit value;
        if (getrlimit(RLIMIT_AS, &value) || value.rlim_cur != 536870912) return 1;
        if (getrlimit(RLIMIT_CORE, &value) || value.rlim_cur != 0) return 1;
        if (getrlimit(RLIMIT_CPU, &value) || value.rlim_cur != 2) return 1;
        if (getrlimit(RLIMIT_FSIZE, &value) || value.rlim_cur != 1025) return 1;
    }
    if (!strcmp(mode, "child") || !strcmp(mode, "probe_child") ||
        !strcmp(mode, "timeout_child") || !strcmp(mode, "probe_timeout")) {
        pid_t child = fork();
        if (child < 0) return 1;
        if (!child) {
            usleep(500000);
            FILE *marker = fopen(getenv("LENS_FIXTURE_MARKER"), "w");
            if (marker) { fputs("survived", marker); fclose(marker); }
            _exit(0);
        }
        FILE *pid = fopen(getenv("LENS_FIXTURE_PID"), "w");
        if (!pid) return 1;
        fprintf(pid, "%ld", (long)child); fclose(pid);
        if (!strcmp(mode, "timeout_child") || !strcmp(mode, "probe_timeout")) sleep(30);
    }
    if (probe) { puts("fixture 1"); return 0; }
    FILE *text = fopen(argv[argc-1], "w");
    if (!text) return 1;
    fputs("Revenue\n\nProfit", text); fclose(text);
    return 0;
}
