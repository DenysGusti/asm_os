#include <iostream>
#include <string>
#include <random>
#include <array>
#include <cstring>

#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

#include "proto.h"

using namespace std;

int create_server_socket(const uint16_t port) {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        cout << "create_server_socket: socket error\n";
        return -1;
    }
    int bool_true = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &bool_true, sizeof(bool_true));
    sockaddr_in addr{
            .sin_family = AF_INET,
            .sin_port = htons(port),
            .sin_addr{.s_addr = INADDR_ANY},
            .sin_zero{}
    };
    if (bind(sockfd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr))) {
        close(sockfd);
        cout << "create_server_socket: bind error\n";
        return -1;
    }
    if (listen(sockfd, 1)) {
        close(sockfd);
        cout << "create_server_socket: listen error\n";
        return -1;
    }
    return sockfd;
}

int accept_wrapper(const int sockfd) {
    int connfd;
    sockaddr_in conn_addr{};
    socklen_t addr_len = sizeof(conn_addr);
    connfd = accept(sockfd, reinterpret_cast<sockaddr *>(&conn_addr), &addr_len);
    return connfd;
}

void set_socket_timeout(const int sockfd, const int ms) {
    timeval timeout{
            .tv_sec = 0,
            .tv_usec = ms * 1'000
    };
    setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
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

bool handle_client(const int connfd) {
    set_socket_timeout(connfd, 50);

    random_device rd;
    mt19937 gen(rd());
    uniform_int_distribution<uint32_t> dist;

    message_unit msg{
            .msg_type = static_cast<uint32_t>(msg_type::CHALLENGE),
            .server_info = 0
    };
    challenge_unit chal{
            .op = dist(gen) % static_cast<uint32_t>(proto_op::OP_END),
            .lhs = dist(gen),
            .rhs = dist(gen),
            .answer = 0
    };

    constexpr size_t buf_sz = sizeof(struct message_unit) + sizeof(struct challenge_unit);
    char buf[buf_sz];
    memcpy(buf, &msg, sizeof(msg));
    memcpy(buf + sizeof(msg), &chal, sizeof(chal));

    if (send(connfd, buf, buf_sz, 0) < 0) {
        cout << "handle_client: send buf error\n";
        return false;
    }

    cout << "sent:\n";
    print_message_unit(msg);
    print_challenge_unit(chal);

    message_unit response_msg{};
    challenge_unit response_chal{};
    if (recv(connfd, buf, buf_sz, 0) < 0) {
        cout << "handle_client: recv error\n";
        return false;
    }

    memcpy(&response_msg, buf, sizeof(msg));
    memcpy(&response_chal, buf + sizeof(msg), sizeof(chal));

    cout << "received:\n";
    print_challenge_unit(response_chal);

    bool correct = false;
    switch (static_cast<proto_op>(chal.op)) {
        case proto_op::ADD:
            correct = response_chal.answer == (chal.lhs + chal.rhs);
            break;
        case proto_op::SUB:
            correct = response_chal.answer == (chal.lhs - chal.rhs);
            break;
        case proto_op::MUL:
            correct = response_chal.answer == (chal.lhs * chal.rhs);
            break;
        case proto_op::LEFT_SHIFT:
            correct = response_chal.answer == (chal.lhs << (chal.rhs % 32));
            break;
        case proto_op::RIGHT_SHIFT:
            correct = response_chal.answer == (chal.lhs >> (chal.rhs % 32));
            break;
        default:
            return false;
    }
    correct &= response_chal.op == chal.op && response_chal.lhs == chal.lhs && response_chal.rhs == chal.rhs;
    correct &= response_msg.server_info == msg.server_info && response_msg.msg_type == msg.msg_type;

    message_unit answer_msg{
            .msg_type = static_cast<uint32_t>(msg_type::SERVER_INFO),
            .server_info = correct ? static_cast<uint32_t>(server_info::CORRECT)
                                   : static_cast<uint32_t>(server_info::WRONG)
    };

    cout << "sent again:\n";
    print_message_unit(answer_msg);

    if (send(connfd, &answer_msg, sizeof(answer_msg), 0) < 0) {
        cout << "handle_client: send answer_msg error\n";
        return false;
    }
    cout << endl;
    return true;
}

int main() {
    constexpr uint16_t port = 1234;
    int sockfd = create_server_socket(port);
    if (sockfd == -1) {
        cout << "main: create_server_socket error\n";
        return 1;
    }
    for (bool handled = true; handled;) {
        int connfd = accept_wrapper(sockfd);
        if (connfd == -1) {
            cout << "main: accept_wrapper error\n";
            break;
        }
        handled = handle_client(connfd);
        close(connfd);
    }
    close(sockfd);
    return 0;
}