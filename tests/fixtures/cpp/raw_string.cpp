// C++ 原生字符串里的花括号：不参与函数帧匹配
#include <string>
std::string query(const std::string& id) {
    const char* sql = R"sql(
SELECT * FROM t WHERE x = {
)sql";
    return std::string(sql) + id;
}
