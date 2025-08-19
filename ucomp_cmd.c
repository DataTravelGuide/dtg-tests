#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define UCOMP_CTRL_PATH "/dev/ucomp_ctrl"
#define UCOMP_IOC_MAGIC 'u'
#define UCOMP_IOC_REGISTER _IOW(UCOMP_IOC_MAGIC, 1, char *)
#define UCOMP_IOC_UNREGISTER _IOW(UCOMP_IOC_MAGIC, 2, char *)

static void usage(const char *prog)
{
    fprintf(stderr, "Usage: %s <register|unregister> <algorithm>\n", prog);
}

int main(int argc, char *argv[])
{
    if (argc != 3) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    const char *cmd = argv[1];
    const char *alg = argv[2];
    int fd = open(UCOMP_CTRL_PATH, O_RDWR);
    if (fd < 0) {
        perror("open");
        return EXIT_FAILURE;
    }

    int ret;
    if (strcmp(cmd, "register") == 0) {
        ret = ioctl(fd, UCOMP_IOC_REGISTER, alg);
    } else if (strcmp(cmd, "unregister") == 0) {
        ret = ioctl(fd, UCOMP_IOC_UNREGISTER, alg);
    } else {
        usage(argv[0]);
        close(fd);
        return EXIT_FAILURE;
    }

    if (ret < 0) {
        perror(cmd);
        close(fd);
        return EXIT_FAILURE;
    }

    close(fd);
    return EXIT_SUCCESS;
}
