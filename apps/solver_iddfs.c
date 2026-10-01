#include "search_cli.h"

int main(int argc, char **argv)
{
    return search_cli(argc, argv, "iddfs", iddfs_solve);
}
