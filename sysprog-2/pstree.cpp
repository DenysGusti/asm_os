#include <iostream>
#include <iomanip>
#include <fstream>
#include <filesystem>
#include <string>
#include <vector>
#include <span>
#include <algorithm>
#include <csignal>
#include <fcntl.h>

using namespace std;

namespace fs = std::filesystem;

struct ProcessNode {
    uint64_t pid = 0;
    uint64_t ppid = 0;
    string name;
    vector<ProcessNode *> children;

    bool collectProcessInfo(const fs::path &process_path) {
        string process_name = process_path.filename();
        // is not digit
        if (process_name.find_first_not_of("0123456789") != string::npos)
            return false;

        pid = stoull(process_name);
        {
            ifstream comm_stream{process_path / "comm"};
            if (!comm_stream.is_open())
                return false;
            comm_stream >> name;
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
            ss >> word;
            ss >> ppid;
        }
        return true;
    }

    [[nodiscard]] string toJSON() const {
        string str;
        str += '{';
        str += R"("pid":)" + to_string(pid + 1) + ',';
        str += R"("name":")" + name + "\",";
        str += R"("children":[)";
        for (const auto child: children) {
            str += child->toJSON();
            if (child != children.back())
                str += ',';
        }
        str += ']';
        str += '}';
        return str;
    }
};

void linkTree(const span<ProcessNode> process_list) {
    for (auto &process_node: process_list)
        if (process_node.ppid != 0) {
            auto &parent = *find_if(process_list.begin(), process_list.end(),
                                    [&](const ProcessNode &node) -> bool {
                                        return node.pid == process_node.ppid;
                                    });
            parent.children.push_back(&process_node);
        }
}

string createJSON(const span<const ProcessNode> process_list) {
    string str;
    str += '[';
    for (const auto &process_node: process_list)
        if (process_node.ppid == 0)
            str += process_node.toJSON() + ',';
    str.pop_back(); // trim last comma
    str += ']';
    return str;
}

int main() {
    vector<ProcessNode> process_list;
    for (const auto &process: fs::directory_iterator("/proc")) {
        ProcessNode process_node;
        if (process_node.collectProcessInfo(process.path()))
            process_list.push_back(process_node);
    }
    linkTree(process_list);
    cout << createJSON(process_list);
    return 0;
}