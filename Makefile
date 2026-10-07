CC ?= cc
CFLAGS ?= -O3 -std=c99 -Wall -Wextra -Wpedantic
FRAMA_C ?= frama-c
RVCC ?= riscv64-unknown-elf-gcc
RVOBJDUMP ?= riscv64-unknown-elf-objdump
RVREADELF ?= riscv64-unknown-elf-readelf
RVSIZE ?= riscv64-unknown-elf-size
RVNM ?= riscv64-unknown-elf-nm
CLANG_FORMAT := $(shell command -v clang-format-20 2>/dev/null || \
	command -v clang-format 2>/dev/null)
C_SOURCES := $(wildcard *.c *.h apps/*.c apps/*.h cube/*.c cube/*.h \
	search/*.c search/*.h target/*.c tests/*.c tests/host/*.c tools/*.c)
SAMPLE_STATE := 21345671111111
SAMPLE_SOLUTION := B' R' D2 R' B R B' R D2 B R'
VECTORS := tests/solutions.txt
# One per rejection path: short, long, cubie digit low, cubie digit high,
# orientation digit low, orientation digit high, non-digit, duplicate, parity.
INVALID_STATES := 1234567111111 123456711111111 02345671111111 82345671111111 \
	12345671111110 12345671111114 1234567111111a 11345671111111 12345671111112

.PHONY: all check check-search test-h1 test-h2 test-h3 \
	find-worst-distance11 benchmark-search \
	regen-idastar-tables rv32i rv32i-info check-rv32i rv32i-asm \
	rv32i-asm-info check-rv32i-asm rv32i-asm-cases prove clean indent

all: solver mini solver_iddfs solver_idastar

solver: solver.c
	$(CC) $(CFLAGS) $< -o $@

mini: mini.c
	$(CC) $(CFLAGS) $< -o $@

SEARCH_INCLUDES := -Iapps -Icube -Isearch
SEARCH_COMMON := cube/cube.c search/timer.c apps/search_cli.c
IDASTAR_SOURCES := search/idastar.c search/idastar_tables.c
IDASTAR_HEADERS := search/idastar_tables.h search/search.h
RV32I_ELF := solver_idastar_rv32i.elf
RV32I_ASM_ELF := solver_idastar_asm_rv32i.elf
RV32I_ASM_CASE_ELFS := solver_idastar_asm_solved.elf \
	solver_idastar_asm_short.elf solver_idastar_asm_distance11.elf \
	solver_idastar_asm_worst11.elf
RV32I_SOURCES := target/start_rv32i.S target/solver_idastar_rv32i.c \
	$(IDASTAR_SOURCES) cube/cube.c
RV32I_ASM_SOURCES := target/solver_idastar_all.S search/idastar_tables.c
RV32I_FLAGS := -O2 -std=c99 -Wall -Wextra -Wpedantic -march=rv32i \
	-mabi=ilp32 -ffreestanding -fno-builtin -ffunction-sections \
	-fdata-sections -msmall-data-limit=0
RV32I_LDFLAGS := -nostdlib -Wl,--gc-sections -Wl,-e,_start \
	-Wl,-Map,solver_idastar_rv32i.map

solver_iddfs: apps/solver_iddfs.c search/iddfs.c $(SEARCH_COMMON) \
		cube/cube.h search/search.h search/search_internal.h apps/search_cli.h
	@$(CC) $(CFLAGS) $(SEARCH_INCLUDES) apps/solver_iddfs.c \
		search/iddfs.c $(SEARCH_COMMON) -o $@

solver_idastar: apps/solver_idastar.c $(IDASTAR_SOURCES) $(SEARCH_COMMON) \
		cube/cube.h $(IDASTAR_HEADERS) search/search_internal.h apps/search_cli.h
	@$(CC) $(CFLAGS) $(SEARCH_INCLUDES) apps/solver_idastar.c \
		$(IDASTAR_SOURCES) $(SEARCH_COMMON) -o $@

search_verify: tests/verify_solution.c cube/cube.c cube/cube.h
	@$(CC) $(CFLAGS) -Icube tests/verify_solution.c cube/cube.c -o $@

test_pdb: tests/test_pdb.c $(IDASTAR_SOURCES) cube/cube.c search/timer.c \
		cube/cube.h $(IDASTAR_HEADERS) search/search_internal.h
	@$(CC) $(CFLAGS) -Icube -Isearch tests/test_pdb.c $(IDASTAR_SOURCES) \
		cube/cube.c search/timer.c -o $@

test_h1_admissibility: tests/host/test_h1_admissibility.c \
		tests/host/exact_bfs.c tests/host/exact_bfs.h $(IDASTAR_SOURCES) \
		cube/cube.c search/timer.c cube/cube.h $(IDASTAR_HEADERS) \
		search/search_internal.h
	@$(CC) $(CFLAGS) -Icube -Isearch tests/host/test_h1_admissibility.c \
		tests/host/exact_bfs.c $(IDASTAR_SOURCES) cube/cube.c search/timer.c -o $@

test-h1: test_h1_admissibility
	./test_h1_admissibility

test_h2_tables: tests/host/test_h2_tables.c $(IDASTAR_SOURCES) cube/cube.c \
		search/timer.c cube/cube.h $(IDASTAR_HEADERS) search/search_internal.h
	@$(CC) $(CFLAGS) -Icube -Isearch tests/host/test_h2_tables.c \
		$(IDASTAR_SOURCES) cube/cube.c search/timer.c -o $@

test-h2: test_h2_tables
	./test_h2_tables

test_h3_optimality: tests/host/test_h3_optimality.c tests/host/exact_bfs.c \
		tests/host/exact_bfs.h $(IDASTAR_SOURCES) cube/cube.c search/timer.c \
		cube/cube.h $(IDASTAR_HEADERS) search/search_internal.h
	@$(CC) $(CFLAGS) -Icube -Isearch -Itests/host \
		tests/host/test_h3_optimality.c tests/host/exact_bfs.c \
		$(IDASTAR_SOURCES) cube/cube.c search/timer.c -o $@

test-h3: test_h3_optimality
	./test_h3_optimality

find_worst_distance11: tests/host/find_worst_distance11.c \
		tests/host/exact_bfs.c tests/host/exact_bfs.h $(IDASTAR_SOURCES) \
		cube/cube.c search/timer.c cube/cube.h $(IDASTAR_HEADERS) \
		search/search_internal.h
	@$(CC) $(CFLAGS) -Icube -Isearch -Itests/host \
		tests/host/find_worst_distance11.c tests/host/exact_bfs.c \
		$(IDASTAR_SOURCES) cube/cube.c search/timer.c -o $@

find-worst-distance11: find_worst_distance11
	./find_worst_distance11

check-search: solver solver_iddfs solver_idastar search_verify test_pdb
	sh tests/check_search.sh
	./test_pdb

benchmark-search: solver_iddfs solver_idastar
	@sh benchmarks/run_search_benchmarks.sh

generate_idastar_tables: tools/generate_idastar_tables.c cube/cube.c cube/cube.h
	@$(CC) $(CFLAGS) -Icube tools/generate_idastar_tables.c cube/cube.c -o $@

regen-idastar-tables: generate_idastar_tables
	./generate_idastar_tables search/idastar_tables.c

$(RV32I_ELF): $(RV32I_SOURCES) cube/cube.h $(IDASTAR_HEADERS)
	$(RVCC) $(RV32I_FLAGS) -Icube -Isearch $(RV32I_SOURCES) \
		$(RV32I_LDFLAGS) -lgcc -o $@

rv32i: $(RV32I_ELF)
	$(RVOBJDUMP) -d $(RV32I_ELF) > solver_idastar_rv32i.dump

rv32i-info: rv32i
	$(RVREADELF) -h $(RV32I_ELF)
	$(RVSIZE) -A $(RV32I_ELF)

check-rv32i: rv32i
	@$(RVREADELF) -h $(RV32I_ELF) | grep -q 'Class:.*ELF32'
	@$(RVREADELF) -h $(RV32I_ELF) | grep -q 'Machine:.*RISC-V'
	@test -z "$$($(RVNM) -u $(RV32I_ELF))" || \
		{ echo 'undefined target symbol found'; exit 1; }
	@if $(RVOBJDUMP) -d $(RV32I_ELF) | \
		grep -Eq '[[:space:]](mul|mulh|mulhsu|mulhu|div|divu|rem|remu)[[:space:]]'; then \
		echo 'forbidden RV32M instruction found'; exit 1; \
	fi
	@static_bytes=$$($(RVSIZE) -A $(RV32I_ELF) | \
		awk '$$1 ~ /^\.(rodata|data|bss|sdata|sbss)(\.|$$)/ { total += $$2 } \
			END { print total + 0 }'); \
		test "$$static_bytes" -le 131072 || \
			{ echo "static data exceeds 128 KiB: $$static_bytes bytes"; exit 1; }; \
		echo "RV32I ELF: PASS ($$static_bytes static bytes, no RV32M instruction)"

$(RV32I_ASM_ELF): $(RV32I_ASM_SOURCES) search/idastar_tables.h
	$(RVCC) $(RV32I_FLAGS) -Icube -Isearch $(RV32I_ASM_SOURCES) \
		-nostdlib -Wl,--gc-sections -Wl,-e,_start \
		-Wl,-Map,solver_idastar_asm_rv32i.map -lgcc -o $@

rv32i-asm: $(RV32I_ASM_ELF)
	$(RVOBJDUMP) -d $(RV32I_ASM_ELF) > solver_idastar_asm_rv32i.dump

rv32i-asm-info: rv32i-asm
	$(RVREADELF) -h $(RV32I_ASM_ELF)
	$(RVSIZE) -A $(RV32I_ASM_ELF)

check-rv32i-asm: rv32i-asm
	@$(RVREADELF) -h $(RV32I_ASM_ELF) | grep -q 'Class:.*ELF32'
	@$(RVREADELF) -h $(RV32I_ASM_ELF) | grep -q 'Machine:.*RISC-V'
	@test -z "$$($(RVNM) -u $(RV32I_ASM_ELF))" || \
		{ echo 'undefined target symbol found'; exit 1; }
	@if $(RVOBJDUMP) -d $(RV32I_ASM_ELF) | \
		grep -Eq '[[:space:]](mul|mulh|mulhsu|mulhu|div|divu|rem|remu)[[:space:]]'; then \
		echo 'forbidden RV32M instruction found'; exit 1; \
	fi
	@static_bytes=$$($(RVSIZE) -A $(RV32I_ASM_ELF) | \
		awk '$$1 ~ /^\.(rodata|data|bss|sdata|sbss)(\.|$$)/ { total += $$2 } \
			END { print total + 0 }'); \
		test "$$static_bytes" -le 131072 || \
			{ echo "static data exceeds 128 KiB: $$static_bytes bytes"; exit 1; }; \
		echo "Hand-written RV32I ELF: PASS ($$static_bytes static bytes, no RV32M instruction)"

solver_idastar_asm_solved.elf: RV32I_CASE_FLAGS := \
	-DTARGET_PERMUTATION_RANK=0 -DTARGET_ORIENTATION_RANK=0 \
	-DTARGET_EXPECTED_LENGTH=0
solver_idastar_asm_short.elf: RV32I_CASE_FLAGS := \
	-DTARGET_PERMUTATION_RANK=1104 -DTARGET_ORIENTATION_RANK=426 \
	-DTARGET_EXPECTED_LENGTH=1
solver_idastar_asm_distance11.elf: RV32I_CASE_FLAGS := \
	-DTARGET_PERMUTATION_RANK=720 -DTARGET_ORIENTATION_RANK=0 \
	-DTARGET_EXPECTED_LENGTH=11
solver_idastar_asm_worst11.elf: RV32I_CASE_FLAGS := \
	-DTARGET_PERMUTATION_RANK=3343 -DTARGET_ORIENTATION_RANK=0 \
	-DTARGET_EXPECTED_LENGTH=11

$(RV32I_ASM_CASE_ELFS): $(RV32I_ASM_SOURCES) search/idastar_tables.h
	$(RVCC) $(RV32I_FLAGS) $(RV32I_CASE_FLAGS) -Icube -Isearch \
		$(RV32I_ASM_SOURCES) -nostdlib -Wl,--gc-sections -Wl,-e,_start \
		-Wl,-Map,$(@:.elf=.map) -lgcc -o $@

rv32i-asm-cases: $(RV32I_ASM_CASE_ELFS)
	@for elf in $(RV32I_ASM_CASE_ELFS); do \
		$(RVOBJDUMP) -d "$$elf" > "$${elf%.elf}.dump"; \
		echo "built $$elf"; \
	done

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
	$(RM) solver mini solver_iddfs solver_idastar search_verify test_pdb \
		test_h1_admissibility test_h2_tables test_h3_optimality \
		find_worst_distance11 \
		generate_idastar_tables $(RV32I_ELF) solver_idastar_rv32i.map \
		solver_idastar_rv32i.dump $(RV32I_ASM_ELF) \
		solver_idastar_asm_rv32i.map solver_idastar_asm_rv32i.dump \
		$(RV32I_ASM_CASE_ELFS) $(RV32I_ASM_CASE_ELFS:.elf=.map) \
		$(RV32I_ASM_CASE_ELFS:.elf=.dump)
	$(RM) solver.exe mini.exe solver_iddfs.exe solver_idastar.exe \
		search_verify.exe test_pdb.exe test_h1_admissibility.exe \
		test_h2_tables.exe test_h3_optimality.exe \
		find_worst_distance11.exe generate_idastar_tables.exe
