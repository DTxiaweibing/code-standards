// 解引用行以 * 开头：是代码，不是块注释续行
int fill(int *p, int n) {
    *p = 1;
    *p = 2;
    *p = 3;
    *p = 4;
    return n;
}
