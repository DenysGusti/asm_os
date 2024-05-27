#include <iostream>
#include <iomanip>
#include <fstream>
#include <filesystem>
#include <string>
#include <vector>
#include <span>
#include <csignal>
#include <fcntl.h>

using namespace std;

namespace fs = std::filesystem;

struct ProcessInfo {
    uint64_t pid = 0;
    string exe;
    string cwd;
    uint64_t base_address = 0;
    char state = 0;
    vector<string> cmdline;

    bool collectProcessInfo(const fs::path &process_path) {
        string process_name = process_path.filename();
        // is not digit
        if (process_name.find_first_not_of("0123456789") != string::npos)
            return false;

        pid = stoull(process_name);
        {
            error_code ec;
            exe = fs::read_symlink(process_path / "exe", ec).string();
            if (ec)
                return false;
        }
        {
            error_code ec;
            cwd = fs::read_symlink(process_path / "cwd", ec).string();
            if (ec)
                return false;
        }
        {
            ifstream maps_stream{process_path / "maps"};
            if (!maps_stream.is_open())
                return false;
            maps_stream >> hex >> base_address;
        }
        {
            ifstream stat_stream{process_path / "stat"};
            if (!stat_stream.is_open())
                return false;
            string line;
            getline(stat_stream, line);
            stringstream ss{line};
            string word;
            ss >> word;
            ss >> word;
            ss >> state;
        }
        {
            ifstream cmdline_stream{process_path / "cmdline"};
            if (!cmdline_stream.is_open())
                return false;
            string line;
            getline(cmdline_stream, line);
            for (size_t new_s = 0, idx = line.find('\"'); idx != string::npos; idx = line.find('\"', new_s))
                if (idx > 0 && line[idx - 1] != '\\') {
                    line.replace(idx, 1, "\\\"");
                    new_s = idx + 2;
                }
            for (auto &c: line)
                if (c == '\0')  // all command line parameters are actually null-separated strings
                    c = ' ';
            stringstream ss{line};
            for (string word; ss >> word;) {
                cmdline.push_back(word);
            }
        }
        return true;
    }

    [[nodiscard]] string toJSON() const {
        string str;
        str += '{';
        str += R"("pid":)" + to_string(pid) + ',';
        str += R"("exe":")" + exe + "\",";
        str += R"("cwd":")" + cwd + "\",";
        str += R"("base_address":)" + to_string(base_address) + ',';
        str += R"("state":")"s + state + "\",";
        str += R"("cmdline":[)";
        for (const auto &cmd_arg: cmdline) {
            str += '"';
            str += cmd_arg;
            str += '"';
            if (&cmd_arg != &cmdline.back())
                str += ',';
        }
        str += ']';
        str += '}';
        return str;
    }
};

string createJSON(const span<const ProcessInfo> process_infos) {
    string str;
    str += '[';
    for (const auto &process_info: process_infos) {
        str += process_info.toJSON();
        if (&process_info != &process_infos.back())
            str += ',';
    }
    str += ']';
    return str;
}

int main() {
    vector<ProcessInfo> process_infos;
    for (const auto &process: fs::directory_iterator("/proc")) {
        ProcessInfo process_info;
        if (process_info.collectProcessInfo(process.path()))
            process_infos.push_back(process_info);
    }
    cout << createJSON(process_infos);
    return 0;
}