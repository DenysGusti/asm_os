#include <iostream>
#include <string>
#include <array>
#include <cstring>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#include "proto.h"

using namespace std;

int connect_to_server(const char *const ip, const uint16_t port) {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        cout << "connect_to_server: socket error\n";
        return -1;
    }
    sockaddr_in addr{
            .sin_family = AF_INET,
            .sin_port = htons(port),
            .sin_addr{},
            .sin_zero{}
    };
    // returns 1 on success, 0 on failure
    if (!inet_pton(AF_INET, ip, &addr.sin_addr)) {
        close(sockfd);
        cout << "connect_to_server: inet_pton error\n";
        return -1;
    }
    if (connect(sockfd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr))) {
        close(sockfd);
        cout << "connect_to_server: connect error\n";
        return -1;
    }
    return sockfd;
}

void print_message_unit(const message_unit &msg) {
    static const array msg_types = {"CHALLENGE", "SERVER_INFO"};
    static const array server_infos = {"CORRECT", "WRONG"};
    cout << "msg_type = " << msg_types[static_cast<size_t>(msg.msg_type)]
         << "\tserver_info = " << server_infos[static_cast<size_t>(msg.server_info)]
         << '\n';
}

void print_challenge_unit(const challenge_unit &chal) {
    static const array proto_ops = {"ADD", "SUB", "MUL", "LEFT_SHIFT", "RIGHT_SHIFT"};
    cout << "op = " << proto_ops[static_cast<size_t>(chal.op)]
         << "\tlhs = " << chal.lhs
         << "\trhs = " << chal.rhs
         << "\tanswer = " << chal.answer
         << '\n';
}

bool process_challenge(const int connfd) {
    message_unit msg{};
    challenge_unit chal{};

    constexpr size_t buf_sz = sizeof(struct message_unit) + sizeof(struct challenge_unit);
    char buf[buf_sz];
    if (recv(connfd, buf, buf_sz, 0) < 0) {
        cout << "process_challenge: recv buf error\n";
        return false;
    }
    memcpy(&msg, buf, sizeof(msg));
    memcpy(&chal, buf + sizeof(msg), sizeof(chal));

    cout << "received:\n";
    print_message_unit(msg);
    print_challenge_unit(chal);

    switch (static_cast<proto_op>(chal.op)) {
        case proto_op::ADD:
            chal.answer = chal.lhs + chal.rhs;
            break;
        case proto_op::SUB:
            chal.answer = chal.lhs - chal.rhs;
            break;
        case proto_op::MUL:
            chal.answer = chal.lhs * chal.rhs;
            break;
        case proto_op::LEFT_SHIFT:
            chal.answer = chal.lhs << (chal.rhs % 32);
            break;
        case proto_op::RIGHT_SHIFT:
            chal.answer = chal.lhs >> (chal.rhs % 32);
            break;
        default:
            return false;
    }

    memcpy(buf, &msg, sizeof(msg));
    memcpy(buf + sizeof(msg), &chal, sizeof(chal));

    if (send(connfd, buf, buf_sz, 0) < 0) {
        cout << "process_challenge: send error\n";
        return false;
    }

    cout << "sent:\n";
    print_challenge_unit(chal);

    message_unit response_msg{};
    if (recv(connfd, &response_msg, sizeof(response_msg), 0) < 0) {
        cout << "process_challenge: recv response_msg error\n";
        return false;
    }

    cout << "received again:\n";
    print_message_unit(response_msg);
    cout << endl;

    if (response_msg.server_info != static_cast<uint32_t>(server_info::CORRECT)) {
        cout << "process_challenge: server_info error\n";
        return false;
    }
    return true;
}

int main() {
    const string ip = "127.0.0.1";
    constexpr uint16_t port = 1234;
    for (bool processed = true; processed;) {
        int connfd = connect_to_server(ip.data(), port);
        if (connfd == -1) {
            cout << "main: connect_to_server error\n";
            return 1;
        }
        processed = process_challenge(connfd);
        close(connfd);
    }
    return 0;
}