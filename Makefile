# Makefile copied from Zoo Mania game

.SILENT:

IMAGE = "therace_dist.d64"
C1541 = c1541
X64 = x64

all: disk

SRC=src/main.s src/about.s src/utils.s src/game.s src/highscores.s
prg:
	cl65 -d -g -Ln therace.sym -u __EXEHDR__ -t c64 -o therace.prg -C therace.cfg ${SRC}

disk: prg
	$(C1541) -format "therace,rq" d64 therace.d64
	$(C1541) therace.d64 -write therace.prg
	$(C1541) therace.d64 -list

dist: prg
	exomizer sfx sys -o therace_exo.prg therace.prg
	$(C1541) -format "therace dist,rq" d64 $(IMAGE)
	$(C1541) $(IMAGE) -write therace_exo.prg "the race"
	$(C1541) $(IMAGE) -list
	rm -f src/*.o therace.prg therace_exo.prg

test: disk
	$(X64) -moncommands therace.sym therace.d64

testdist: dist
	$(X64) -moncommands therace.sym $(IMAGE)

clean:
	rm -f src/*.o therace.prg therace_exo.prg therace.d64 therace.sym $(IMAGE)
