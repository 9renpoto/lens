#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* The helper supervises one process group per phase. Escaped groups are excluded. */
static volatile sig_atomic_t cancelled;
static void cancel(int signal_number) { (void)signal_number; cancelled = 1; }
static long long now_ms(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) return -1;
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static int bound(int resource, rlim_t value) {
    struct rlimit limit = {value, value};
    return setrlimit(resource, &limit);
}
static int phase(char *const args[], const char *log, long milliseconds, long bytes) {
    int fd = open(log, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    int errors[2];
    if (fd < 0) return -3;
    if (pipe2(errors, O_CLOEXEC)) { close(fd); return -3; }
    long long started = now_ms();
    if (started < 0) { close(fd); close(errors[0]); close(errors[1]); return -3; }
    pid_t pid = fork();
    if (!pid) {
        close(errors[0]);
        int input = open("/dev/null", O_RDONLY);
        if (setsid() < 0 || input < 0 || dup2(input, 0) < 0 ||
            dup2(fd, 1) < 0 || dup2(fd, 2) < 0 ||
            bound(RLIMIT_CORE, 0) || bound(RLIMIT_AS, 536870912) ||
            bound(RLIMIT_CPU, (milliseconds + 999) / 1000) ||
            bound(RLIMIT_FSIZE, (rlim_t)bytes + 1)) {
            int error = EIO;
            (void)write(errors[1], &error, sizeof(error));
            _exit(126);
        }
        close(input); close(fd);
        execv(args[0], args);
        int error = errno;
        (void)write(errors[1], &error, sizeof(error));
        _exit(127);
    }
    close(fd); close(errors[1]);
    if (pid < 0) { close(errors[0]); return -3; }
    int status = 0, result = -3, reaped = 0;
    for (;;) {
        pid_t waited = waitpid(pid, &status, WNOHANG);
        if (waited == pid) { reaped = 1; result = WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 1; break; }
        if (waited < 0 && errno != EINTR) break;
        long long current = now_ms();
        if (cancelled) { result = -4; break; }
        if (current < 0) break;
        if (current - started >= milliseconds) { result = -2; break; }
        struct pollfd owner = {STDIN_FILENO, POLLIN | POLLHUP, 0};
        int ready = poll(&owner, 1, 5);
        if (ready < 0 && errno != EINTR) break;
        if (ready > 0 && (owner.revents & (POLLIN | POLLHUP | POLLERR))) { result = -4; break; }
    }
    /* Kill both the group and direct child to cover cancellation before setsid. */
    (void)kill(-pid, SIGKILL);
    if (!reaped) {
        (void)kill(pid, SIGKILL);
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    int launch_error = 0;
    ssize_t length = read(errors[0], &launch_error, sizeof(launch_error));
    close(errors[0]);
    if (length > 0 && result != -2 && result != -4)
        return launch_error == ENOENT ? -1 : -3;
    return result;
}
static long number(const char *raw, long maximum) {
    char *end = NULL;
    errno = 0;
    long value = strtol(raw, &end, 10);
    return errno || !*raw || *end || value < 1 || value > maximum ? -1 : value;
}
int main(int argc, char **argv) {
    if (argc == 4 && !strcmp(argv[1], "--signal")) {
        long pid = number(argv[3], 2147483647);
        int sig = !strcmp(argv[2], "TERM") ? SIGTERM : !strcmp(argv[2], "KILL") ? SIGKILL : !strcmp(argv[2], "CONT") ? SIGCONT : 0;
        if (pid <= 1 || !sig) return 1;
        return kill((pid_t)pid, sig) && errno != ESRCH ? 1 : 0;
    }
    const char *result = "process_error";
    if (argc != 7) { puts("invalid_options"); return 0; }
    long milliseconds = number(argv[5], 30000), bytes = number(argv[6], 8388608);
    if (milliseconds < 0 || bytes < 0) { puts("invalid_options"); return 0; }
#ifndef __linux__
    puts("unsupported_platform"); return 0;
#endif
    signal(SIGTERM, cancel); signal(SIGINT, cancel); signal(SIGHUP, cancel);
    signal(SIGPIPE, SIG_IGN);
    size_t length = strlen(argv[4]) + 5;
    char *log = malloc(length);
    if (!log) { puts(result); return 0; }
    snprintf(log, length, "%s.log", argv[4]);
    char *probe[] = {argv[1], "-v", NULL};
    int status = phase(probe, log, milliseconds < 2000 ? milliseconds : 2000, 4096);
    if (status) {
        result = status == -2 ? "timeout" : status == -3 || status == -4 ? "process_error" : "extractor_unavailable";
        goto done;
    }
    int source = open(log, O_RDONLY | O_CLOEXEC);
    int target = open(argv[4], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    char version[2048];
    ssize_t count = source < 0 ? -1 : read(source, version, sizeof(version));
    if (source >= 0) close(source);
    if (target < 0 || count < 0 || write(target, version, (size_t)count) != count) {
        if (target >= 0) close(target);
        goto done;
    }
    close(target);
    char *extract[] = {argv[1], "-enc", "UTF-8", "-eol", "unix", "-nopgbrk", argv[2], argv[3], NULL};
    status = phase(extract, log, milliseconds, bytes);
    if (status == -2) { result = "timeout"; goto done; }
    if (status == -4 || status == -3) goto done;
    if (status == -1) { result = "extractor_unavailable"; goto done; }
    struct stat info;
    int exists = stat(argv[3], &info) == 0;
    if (exists && info.st_size > bytes) result = "output_limit";
    else if (status) result = "unreadable";
    else if (!exists) result = "extractor_unavailable";
    else result = "ok";
done:
    unlink(log); free(log);
    puts(result);
    return 0;
}
