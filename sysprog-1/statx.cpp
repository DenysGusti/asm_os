#include <iostream>
#include <sys/stat.h>
#include <fcntl.h>

using namespace std;

void printPermissions(const uint16_t mode) {
    char permissions[] = "---------";
    if (mode & S_IRUSR)
        permissions[0] = 'r';
    if (mode & S_IWUSR)
        permissions[1] = 'w';
    if (mode & S_IXUSR)
        permissions[2] = 'x';
    if (mode & S_IRGRP)
        permissions[3] = 'r';
    if (mode & S_IWGRP)
        permissions[4] = 'w';
    if (mode & S_IXGRP)
        permissions[5] = 'x';
    if (mode & S_IROTH)
        permissions[6] = 'r';
    if (mode & S_IWOTH)
        permissions[7] = 'w';
    if (mode & S_IXOTH)
        permissions[8] = 'x';
    cout << permissions << '\n';
}

int main(const int argc, const char *argv[]) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <absolute_path_to_file>\n" ;
        return 1;
    }
    const char *file_path = argv[1];
    // const char *file_path = R"(/home)";
    struct statx stx{};

    statx(AT_FDCWD, file_path, AT_SYMLINK_NOFOLLOW, STATX_UID | STATX_GID, &stx);
    cout << "UID: " << stx.stx_uid << ", GID: " << stx.stx_gid << '\n';
    statx(AT_FDCWD, file_path, AT_SYMLINK_NOFOLLOW, STATX_SIZE, &stx);
    cout << "Size: " << stx.stx_size << '\n';
    statx(AT_FDCWD, file_path, AT_SYMLINK_NOFOLLOW, STATX_MODE, &stx);
    printPermissions(stx.stx_mode);

    // statx(AT_FDCWD, file_path, AT_SYMLINK_NOFOLLOW, 0xa8, &stx);
    return 0;
}