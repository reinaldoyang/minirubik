CC ?= cc
CFLAGS ?= -O3 -std=c99 -Wall -Wextra -Wpedantic
FRAMA_C ?= frama-c
CLANG_FORMAT := $(shell command -v clang-format-20 2>/dev/null || \
	command -v clang-format 2>/dev/null)
C_SOURCES := $(wildcard *.c *.h apps/*.c apps/*.h cube/*.c cube/*.h \
	search/*.c search/*.h tests/*.c)
SAMPLE_STATE := 21345671111111
SAMPLE_SOLUTION := B' R' D2 R' B R B' R D2 B R'
VECTORS := tests/solutions.txt
# One per rejection path: short, long, cubie digit low, cubie digit high,
# orientation digit low, orientation digit high, non-digit, duplicate, parity.
INVALID_STATES := 1234567111111 123456711111111 02345671111111 82345671111111 \
	12345671111110 12345671111114 1234567111111a 11345671111111 12345671111112

.PHONY: all check check-search benchmark-search prove clean indent

all: solver mini solver_iddfs solver_idastar

solver: solver.c
	$(CC) $(CFLAGS) $< -o $@

mini: mini.c
	$(CC) $(CFLAGS) $< -o $@

SEARCH_INCLUDES := -Iapps -Icube -Isearch
SEARCH_COMMON := cube/cube.c search/timer.c apps/search_cli.c

solver_iddfs: apps/solver_iddfs.c search/iddfs.c $(SEARCH_COMMON) \
		cube/cube.h search/search.h search/search_internal.h apps/search_cli.h
	@$(CC) $(CFLAGS) $(SEARCH_INCLUDES) apps/solver_iddfs.c \
		search/iddfs.c $(SEARCH_COMMON) -o $@

solver_idastar: apps/solver_idastar.c search/idastar.c $(SEARCH_COMMON) \
		cube/cube.h search/search.h search/search_internal.h apps/search_cli.h
	@$(CC) $(CFLAGS) $(SEARCH_INCLUDES) apps/solver_idastar.c \
		search/idastar.c $(SEARCH_COMMON) -o $@

search_verify: tests/verify_solution.c cube/cube.c cube/cube.h
	@$(CC) $(CFLAGS) -Icube tests/verify_solution.c cube/cube.c -o $@

test_pdb: tests/test_pdb.c search/idastar.c cube/cube.c search/timer.c \
		cube/cube.h search/search.h search/search_internal.h
	@$(CC) $(CFLAGS) -Icube -Isearch tests/test_pdb.c search/idastar.c \
		cube/cube.c search/timer.c -o $@

check-search: solver solver_iddfs solver_idastar search_verify test_pdb
	sh tests/check_search.sh
	./test_pdb

benchmark-search: solver_iddfs solver_idastar
	@sh benchmarks/run_search_benchmarks.sh

check: solver mini $(VECTORS)
	./solver --self-test
	@expected=$$(mktemp); actual=$$(mktemp); \
		trap 'rm -f "$$expected" "$$actual"' 0 1 2 15; \
		count=0; \
		while IFS='|' read -r state solution; do \
			case "$$state" in ""|\#*) continue ;; esac; \
			printf '%s\n' "$$solution" >"$$expected"; \
			for binary in ./solver ./mini; do \
				$$binary "$$state" >"$$actual"; \
				status=$$?; \
				test $$status -eq 0 || { \
					echo "$$binary $$state: exit status $$status"; exit 1; }; \
				cmp -s "$$actual" "$$expected" || { \
					echo "$$binary $$state: output mismatch"; \
					echo "  expected: $$solution"; \
					printf '  got:      '; cat "$$actual"; \
					echo "  ($$(wc -c <"$$expected") bytes expected, \
$$(wc -c <"$$actual") produced)"; exit 1; }; \
			done; \
			count=$$((count + 1)); \
		done <$(VECTORS); \
		echo "$$count solution vectors matched by solver and mini"
	@for binary in ./solver ./mini; do \
		for bad in $(INVALID_STATES); do \
			$$binary "$$bad" >/dev/null 2>&1; \
			status=$$?; \
			test $$status -eq 2 || { \
				echo "$$binary $$bad: expected status 2, got $$status"; exit 1; }; \
		done; \
		$$binary >/dev/null 2>&1; \
		status=$$?; \
		test $$status -eq 2 || { \
			echo "$$binary with no argument: expected status 2, got $$status"; \
			exit 1; }; \
		$$binary $(SAMPLE_STATE) $(SAMPLE_STATE) >/dev/null 2>&1; \
		status=$$?; \
		test $$status -eq 2 || { \
			echo "$$binary with two arguments: expected status 2, got $$status"; \
			exit 1; }; \
		$$binary $(SAMPLE_STATE) >&- 2>/dev/null; \
		status=$$?; \
		test $$status -eq 1 || { \
			echo "$$binary with stdout closed: expected status 1, got $$status"; \
			exit 1; }; \
	done
	@./solver --self-test >&- 2>/dev/null; \
		status=$$?; \
		test $$status -eq 1 || { \
			echo "solver --self-test with stdout closed: expected 1, got $$status"; \
			exit 1; }
	@echo "invalid input rejected with status 2, unwritable stdout with status 1"

prove: solver.c
	@log=$$(mktemp); trap 'rm -f "$$log"' 0 1 2 15; \
		$(FRAMA_C) -wp -wp-fct quarter_turn,rank_state,valid,parse_state \
		-wp-rte -rte-verbose 0 -wp-prover alt-ergo -wp-timeout 20 \
		-wp-cache none solver.c >"$$log" 2>&1; rc=$$?; \
		grep -Fvx -e '[wp] Warning: Skipped RTE guards: unaligned pointers (\aligned not supported)' \
		-e '[wp] Warning: Skipped RTE guards: invalid function pointer calls (\valid_function not supported)' "$$log"; \
		test $$rc -eq 0 && awk '$$1 == "[wp]" && $$2 == "Proved" && $$3 == "goals:" && $$4 > 0 && $$4 == $$6 { ok = 1 } END { exit !ok }' "$$log" && \
		! grep -Eq '(^|[[:space:]])(Timeout|Unknown|Failed):' "$$log"

indent:
ifeq ($(CLANG_FORMAT),)
	$(error clang-format 20 not found)
endif
	@$(CLANG_FORMAT) --version | grep -q 'version 20' || \
		{ echo "error: clang-format version 20 required"; exit 1; }
	$(CLANG_FORMAT) -i $(C_SOURCES)

clean:
	$(RM) solver mini solver_iddfs solver_idastar search_verify test_pdb
	$(RM) solver.exe mini.exe solver_iddfs.exe solver_idastar.exe search_verify.exe test_pdb.exe
