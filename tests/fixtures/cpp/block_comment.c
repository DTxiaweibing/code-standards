// 块注释续行以 * 开头：仍然算注释，不能计入有效行
int add(int a, int b) {
    /* 说明
     * 第二行
     */
    int c = a + b;
    return c;
}
