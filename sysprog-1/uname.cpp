#include <iostream>
#include <sys/utsname.h>

using namespace std;

void printKernelInfo() {
    utsname buf{};
    uname(&buf);
    cout << "Hostname: " << buf.nodename << '\n'
         << "OS: " << buf.sysname << '\n'
         << "Version: " << buf.version << '\n'
         << "Release: " << buf.release << '\n';
}

int main() {
    printKernelInfo();
    return 0;
}
