#include <iostream>
#include <fstream>
#include <filesystem>
#include <csignal>
#include <fcntl.h>

using namespace std;

namespace fs = std::filesystem;

int main(const int argc, const char *argv[]) {
    if (argc != 2) {
        cerr << "Usage: " << argv[0] << " <absolute_path_to_file>\n";
        return 1;
    }
    const string processNameToKill = argv[1];

    for (const auto &process: fs::directory_iterator("/proc")) {
        string processName = process.path().filename();
        if (processName.find_first_not_of("0123456789") == string::npos) {  // is digit
            fs::path processComm = process.path() / "comm";
            ifstream comm{processComm};
            string processCommandName;
            comm >> processCommandName;
            cout << processCommandName << '\n' << processName << endl;
            if (processCommandName == processNameToKill) {
                const int pid = stoi(processName);
                kill(pid, SIGKILL);
            }
        }
    }
    return 0;
}
