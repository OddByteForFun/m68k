# Émulateur CPU Motorola 68000 en Zig

![Zig Version](https://img.shields.io/badge/Zig-0.16-orange?logo=zig)

## Description

Projet d'émulation du **Motorola 68000**.  
Il s'agit d'un projet plus global visant à émuler la console **Sega Mega Drive / Genesis**. 
L'objectif est d'atteindre une précision compatible avec les jeux commerciaux.  

## Composition du projet

```
m68k/
├── src/
│   ├── m68k.zig          # Structure du CPU (registres, SR, interruptions, reset, step())
│   ├── decode.zig        # Décodeur principal + helpers d'adressage (EA)
│   └── decode/
│       ├── bloc0.zig     # OR, SBCD, DIVU, DIVS
│       ├── bloc1.zig     # NOP, TRAP, SWAP, MOVEM, EXT, Scc, JSR, JMP, RESET, STOP, RTE, RTR
│       ├── bloc2.zig     # ADDQ, SUBQ, shifts/rotates immédiats
│       ├── bloc3.zig     # Shifts/rotates par registre, NBCD, TAS, MOVE, LEA, PEA
│       ├── bloc6.zig     # Bcc, BSR, DBcc, SUB, SUBA, SUBX
│       ├── bloc7.zig     # MOVEQ, OR, AND, SUB, ADD, CMP, Scc, shifts/rotates, bit ops
│       ├── bloc8.zig     # OR, SBCD, DIVU, DIVS (bloc 8 et 0 partagent des encodings)
│       ├── bloc10.zig    # AND, ADD, shifts/rotates mémoire
│       ├── bloc11.zig    # CMP, CMPA, CMPI, CMPM, EOR, AND
│       ├── bloc13.zig    # ADD, ADDA, ADDX, AND, OR, shifts/rotates, bit ops
│       └── blocC.zig     # ABCD, AND, OR, MULU, MULS, EXG
├── tests/
│   ├── cpu_test.zig      # Tests unitaires opcode par opcode
│   ├── cpu_json_test.zig # Harness de tests via JSON MAME (317 500 cas)
│   └── json_opcodes/     # 127 fichiers JSON MAME (2 500 cas chacun)
└── build.zig             # Build : `zig build test-cpu-{opcodes,json}`
```

L'émulateur est **indépendant de tout système hôte** : `src/m68k.zig` expose une structure CPU avec `step(bus)`. Le bus est une interface générique (lecture/écriture mémoire, signaux d'interruption). Il peut être branché à n'importe quel système.

## Compilation 

```
Binaire : zig build -Doptimize=ReleaseFast
Execution test MAME : zig build -Doptimize=ReleaseFast test-cpu-json --summary all
Exécution tests :  zig build -Doptimize=ReleaseFast test-cpu-opcodes --summary all
Test de timing :   zig build -Doptimize=ReleaseFast test-cpu-timing
```

## Résultats des tests JSON MAME

Tests exécutés via `zig build test-cpu-json -Doptimize=ReleaseFast` — 127 fichiers JSON, 2 500 test cases par fichier, soit **317 500 séquences** validant l'état complet du CPU (registres, SR, mémoire) après chaque instruction.

Ces tests proviennent de https://github.com/SingleStepTests/m68000.git.  
Ils sont générés depuis MAME.

Ils sont convertis puis copiés dans tests/json_opcodes/.

```
git clone https://github.com/SingleStepTests/m68000.git
python ./decode
```


| Opcode | Tests | Réussite | Échecs | Taux | Paires | Impaire |
|--------|------:|---------:|-------:|-----:|:------:|--------:|
| ABCD | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| ADD.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| ADD.l | 2500 | 2171 | 5282 | ![86.8%](https://img.shields.io/badge/86.8%25-green) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ADD.w | 2500 | 2162 | 5363 | ![86.5%](https://img.shields.io/badge/86.5%25-green) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ADDA.l | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| ADDA.w | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| ADDX.b | 2500 | 2236 | 783 | ![89.4%](https://img.shields.io/badge/89.4%25-green) | ![89.4%](https://img.shields.io/badge/89.4%25-green) | ![—](https://img.shields.io/badge/---lightgrey) |
| ADDX.l | 2500 | 1671 | 14464 | ![66.8%](https://img.shields.io/badge/66.8%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ADDX.w | 2500 | 1683 | 13515 | ![67.3%](https://img.shields.io/badge/67.3%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| AND.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| AND.l | 2500 | 1500 | 16464 | ![60.0%](https://img.shields.io/badge/60.0%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| AND.w | 2500 | 1431 | 17411 | ![57.2%](https://img.shields.io/badge/57.2%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ANDItoCCR | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| ANDItoSR | 2500 | 1293 | 9507 | ![51.7%](https://img.shields.io/badge/51.7%25-orange) | ![51.7%](https://img.shields.io/badge/51.7%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| ASL.b | 2500 | 2491 | 9 | ![99.6%](https://img.shields.io/badge/99.6%25-brightgreen) | ![99.6%](https://img.shields.io/badge/99.6%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| ASL.l | 2500 | 2487 | 13 | ![99.5%](https://img.shields.io/badge/99.5%25-brightgreen) | ![99.5%](https://img.shields.io/badge/99.5%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| ASL.w | 2500 | 1908 | 5529 | ![76.3%](https://img.shields.io/badge/76.3%25-green) | ![89.1%](https://img.shields.io/badge/89.1%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ASR.b | 2500 | 2488 | 12 | ![99.5%](https://img.shields.io/badge/99.5%25-brightgreen) | ![99.5%](https://img.shields.io/badge/99.5%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| ASR.l | 2500 | 2491 | 9 | ![99.6%](https://img.shields.io/badge/99.6%25-brightgreen) | ![99.6%](https://img.shields.io/badge/99.6%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| ASR.w | 2500 | 1934 | 5526 | ![77.4%](https://img.shields.io/badge/77.4%25-green) | ![90.1%](https://img.shields.io/badge/90.1%25-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| Bcc | 2500 | 1824 | 9824 | ![73.0%](https://img.shields.io/badge/73.0%25-orange) | ![73.0%](https://img.shields.io/badge/73.0%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| BCHG | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| BCLR | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| BSET | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| BSR | 2500 | 1229 | 18631 | ![49.2%](https://img.shields.io/badge/49.2%25-orange) | ![49.2%](https://img.shields.io/badge/49.2%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| BTST | 2500 | 2442 | 87 | ![97.7%](https://img.shields.io/badge/97.7%25-brightgreen) | ![97.7%](https://img.shields.io/badge/97.7%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| CHK | 2500 | 2306 | 194 | ![92.2%](https://img.shields.io/badge/92.2%25-brightgreen) | ![92.2%](https://img.shields.io/badge/92.2%25-brightgreen) | ![92.2%](https://img.shields.io/badge/92.2%25-brightgreen) |
| CLR.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| CLR.l | 2500 | 1529 | 15537 | ![61.2%](https://img.shields.io/badge/61.2%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| CLR.w | 2500 | 1481 | 16147 | ![59.2%](https://img.shields.io/badge/59.2%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| CMP.b | 2500 | 2224 | 1325 | ![89.0%](https://img.shields.io/badge/89.0%25-green) | ![89.0%](https://img.shields.io/badge/89.0%25-green) | ![—](https://img.shields.io/badge/---lightgrey) |
| CMP.l | 2500 | 1465 | 14933 | ![58.6%](https://img.shields.io/badge/58.6%25-orange) | ![85.6%](https://img.shields.io/badge/85.6%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| CMP.w | 2500 | 1462 | 14701 | ![58.5%](https://img.shields.io/badge/58.5%25-orange) | ![84.9%](https://img.shields.io/badge/84.9%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| CMPA.l | 2500 | 1670 | 13271 | ![66.8%](https://img.shields.io/badge/66.8%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| CMPA.w | 2500 | 1664 | 13215 | ![66.6%](https://img.shields.io/badge/66.6%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| DBcc | 2500 | 1868 | 9908 | ![74.7%](https://img.shields.io/badge/74.7%25-orange) | ![74.7%](https://img.shields.io/badge/74.7%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| DIVS | 2500 | 493 | 13480 | ![19.7%](https://img.shields.io/badge/19.7%25-red) | ![32.5%](https://img.shields.io/badge/32.5%25-orange) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| DIVU | 2500 | 859 | 12778 | ![34.4%](https://img.shields.io/badge/34.4%25-orange) | ![55.6%](https://img.shields.io/badge/55.6%25-orange) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| EOR.b | 2500 | 2132 | 1090 | ![85.3%](https://img.shields.io/badge/85.3%25-green) | ![85.3%](https://img.shields.io/badge/85.3%25-green) | ![—](https://img.shields.io/badge/---lightgrey) |
| EOR.l | 2500 | 1346 | 16695 | ![53.8%](https://img.shields.io/badge/53.8%25-orange) | ![92.6%](https://img.shields.io/badge/92.6%25-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| EOR.w | 2500 | 1290 | 16583 | ![51.6%](https://img.shields.io/badge/51.6%25-orange) | ![89.7%](https://img.shields.io/badge/89.7%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| EORItoCCR | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| EORItoSR | 2500 | 22 | 10905 | ![0.9%](https://img.shields.io/badge/0.9%25-red) | ![0.9%](https://img.shields.io/badge/0.9%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| EXG | 2500 | 834 | 6021 | ![33.4%](https://img.shields.io/badge/33.4%25-orange) | ![33.4%](https://img.shields.io/badge/33.4%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| EXT.l | 2500 | 0 | 3805 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| EXT.w | 2500 | 0 | 12322 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ILLEGAL_LINEA | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| ILLEGAL_LINEF | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| JMP | 2500 | 1272 | 19017 | ![50.9%](https://img.shields.io/badge/50.9%25-orange) | ![50.9%](https://img.shields.io/badge/50.9%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| JSR | 2500 | 1341 | 16868 | ![53.6%](https://img.shields.io/badge/53.6%25-orange) | ![53.6%](https://img.shields.io/badge/53.6%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| LEA | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| LINK | 2500 | 2174 | 335 | ![87.0%](https://img.shields.io/badge/87.0%25-green) | ![87.0%](https://img.shields.io/badge/87.0%25-green) | ![—](https://img.shields.io/badge/---lightgrey) |
| LSL.b | 2500 | 2486 | 14 | ![99.4%](https://img.shields.io/badge/99.4%25-brightgreen) | ![99.4%](https://img.shields.io/badge/99.4%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| LSL.l | 2500 | 2493 | 7 | ![99.7%](https://img.shields.io/badge/99.7%25-brightgreen) | ![99.7%](https://img.shields.io/badge/99.7%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| LSL.w | 2500 | 1944 | 5132 | ![77.8%](https://img.shields.io/badge/77.8%25-green) | ![89.5%](https://img.shields.io/badge/89.5%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| LSR.b | 2500 | 2494 | 6 | ![99.8%](https://img.shields.io/badge/99.8%25-brightgreen) | ![99.8%](https://img.shields.io/badge/99.8%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| LSR.l | 2500 | 2488 | 12 | ![99.5%](https://img.shields.io/badge/99.5%25-brightgreen) | ![99.5%](https://img.shields.io/badge/99.5%25-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| LSR.w | 2500 | 1938 | 5588 | ![77.5%](https://img.shields.io/badge/77.5%25-green) | ![90.0%](https://img.shields.io/badge/90.0%25-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVE.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| MOVE.l | 2500 | 1658 | 1792 | ![66.3%](https://img.shields.io/badge/66.3%25-orange) | ![66.3%](https://img.shields.io/badge/66.3%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| MOVE.q | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| MOVE.w | 2500 | 1938 | 564 | ![77.5%](https://img.shields.io/badge/77.5%25-green) | ![77.5%](https://img.shields.io/badge/77.5%25-green) | ![—](https://img.shields.io/badge/---lightgrey) |
| MOVEA.l | 2500 | 1655 | 14070 | ![66.2%](https://img.shields.io/badge/66.2%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEA.w | 2500 | 1658 | 13901 | ![66.3%](https://img.shields.io/badge/66.3%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEfromSR | 2500 | 1522 | 15278 | ![60.9%](https://img.shields.io/badge/60.9%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEfromUSP | 2500 | 0 | 12108 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| MOVEM.l | 2500 | 1150 | 24358 | ![46.0%](https://img.shields.io/badge/46.0%25-orange) | ![88.2%](https://img.shields.io/badge/88.2%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEM.w | 2500 | 1161 | 23244 | ![46.4%](https://img.shields.io/badge/46.4%25-orange) | ![88.1%](https://img.shields.io/badge/88.1%25-green) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEP.l | 2500 | 0 | 8099 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| MOVEP.w | 2500 | 0 | 5306 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| MOVEtoCCR | 2500 | 0 | 19785 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEtoSR | 2500 | 15 | 18342 | ![0.6%](https://img.shields.io/badge/0.6%25-red) | ![1.0%](https://img.shields.io/badge/1.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MOVEtoUSP | 2500 | 0 | 13274 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| MULS | 2500 | 1 | 17538 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.1%](https://img.shields.io/badge/0.1%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| MULU | 2500 | 1 | 18264 | ![0.0%](https://img.shields.io/badge/0.0%25-red) | ![0.1%](https://img.shields.io/badge/0.1%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| NBCD | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| NEG.b | 2500 | 1247 | 1253 | ![49.9%](https://img.shields.io/badge/49.9%25-orange) | ![49.9%](https://img.shields.io/badge/49.9%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| NEG.l | 2500 | 797 | 15994 | ![31.9%](https://img.shields.io/badge/31.9%25-orange) | ![51.5%](https://img.shields.io/badge/51.5%25-orange) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| NEG.w | 2500 | 767 | 15952 | ![30.7%](https://img.shields.io/badge/30.7%25-orange) | ![49.7%](https://img.shields.io/badge/49.7%25-orange) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| NEGX.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| NEGX.l | 2500 | 1543 | 15315 | ![61.7%](https://img.shields.io/badge/61.7%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| NEGX.w | 2500 | 1537 | 15239 | ![61.5%](https://img.shields.io/badge/61.5%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| NOP | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| NOT.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| NOT.l | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| NOT.w | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| OR.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| OR.l | 2500 | 1423 | 17087 | ![56.9%](https://img.shields.io/badge/56.9%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| OR.w | 2500 | 1438 | 16673 | ![57.5%](https://img.shields.io/badge/57.5%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ORItoCCR | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| ORItoSR | 2500 | 14 | 11449 | ![0.6%](https://img.shields.io/badge/0.6%25-red) | ![0.6%](https://img.shields.io/badge/0.6%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| PEA | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| RESET | 2500 | 1233 | 10000 | ![49.3%](https://img.shields.io/badge/49.3%25-orange) | ![49.3%](https://img.shields.io/badge/49.3%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROL.b | 2500 | 190 | 3982 | ![7.6%](https://img.shields.io/badge/7.6%25-red) | ![7.6%](https://img.shields.io/badge/7.6%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROL.l | 2500 | 180 | 3777 | ![7.2%](https://img.shields.io/badge/7.2%25-red) | ![7.2%](https://img.shields.io/badge/7.2%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROL.w | 2500 | 190 | 8511 | ![7.6%](https://img.shields.io/badge/7.6%25-red) | ![8.8%](https://img.shields.io/badge/8.8%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ROR.b | 2500 | 204 | 4170 | ![8.2%](https://img.shields.io/badge/8.2%25-red) | ![8.2%](https://img.shields.io/badge/8.2%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROR.l | 2500 | 185 | 4217 | ![7.4%](https://img.shields.io/badge/7.4%25-red) | ![7.4%](https://img.shields.io/badge/7.4%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROR.w | 2500 | 156 | 8965 | ![6.2%](https://img.shields.io/badge/6.2%25-red) | ![7.3%](https://img.shields.io/badge/7.3%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ROXL.b | 2500 | 175 | 4047 | ![7.0%](https://img.shields.io/badge/7.0%25-red) | ![7.0%](https://img.shields.io/badge/7.0%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROXL.l | 2500 | 196 | 3748 | ![7.8%](https://img.shields.io/badge/7.8%25-red) | ![7.8%](https://img.shields.io/badge/7.8%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROXL.w | 2500 | 188 | 8216 | ![7.5%](https://img.shields.io/badge/7.5%25-red) | ![8.7%](https://img.shields.io/badge/8.7%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| ROXR.b | 2500 | 184 | 4247 | ![7.4%](https://img.shields.io/badge/7.4%25-red) | ![7.4%](https://img.shields.io/badge/7.4%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROXR.l | 2500 | 177 | 4246 | ![7.1%](https://img.shields.io/badge/7.1%25-red) | ![7.1%](https://img.shields.io/badge/7.1%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| ROXR.w | 2500 | 165 | 8579 | ![6.6%](https://img.shields.io/badge/6.6%25-red) | ![7.6%](https://img.shields.io/badge/7.6%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| RTE | 2500 | 14 | 21017 | ![0.6%](https://img.shields.io/badge/0.6%25-red) | ![0.6%](https://img.shields.io/badge/0.6%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| RTR | 2500 | 153 | 20981 | ![6.1%](https://img.shields.io/badge/6.1%25-red) | ![6.1%](https://img.shields.io/badge/6.1%25-red) | ![—](https://img.shields.io/badge/---lightgrey) |
| RTS | 2500 | 1263 | 12365 | ![50.5%](https://img.shields.io/badge/50.5%25-orange) | ![50.5%](https://img.shields.io/badge/50.5%25-orange) | ![—](https://img.shields.io/badge/---lightgrey) |
| SBCD | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey) |
| Scc | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| STOP | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![—](https://img.shields.io/badge/---lightgrey)
| SUB.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| SUB.l | 2500 | 1599 | 14441 | ![64.0%](https://img.shields.io/badge/64.0%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| SUB.w | 2500 | 1579 | 14589 | ![63.2%](https://img.shields.io/badge/63.2%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| SUBX.b | 2500 | 2230 | 800 | ![89.2%](https://img.shields.io/badge/89.2%25-green) | ![89.2%](https://img.shields.io/badge/89.2%25-green) | ![—](https://img.shields.io/badge/---lightgrey) |
| SUBX.l | 2500 | 1673 | 14450 | ![66.9%](https://img.shields.io/badge/66.9%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| SUBX.w | 2500 | 1646 | 14118 | ![65.8%](https://img.shields.io/badge/65.8%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| SWAP | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| TAS | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| TRAP | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| TRAPV | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| TST.b | 2500 | 2500 | 0 | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) |
| TST.l | 2500 | 1524 | 15655 | ![61.0%](https://img.shields.io/badge/61.0%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| TST.w | 2500 | 1507 | 15714 | ![60.3%](https://img.shields.io/badge/60.3%25-orange) | ![Complet](https://img.shields.io/badge/Complet-brightgreen) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |
| UNLINK | 2500 | 7 | 20557 | ![0.3%](https://img.shields.io/badge/0.3%25-red) | ![0.5%](https://img.shields.io/badge/0.5%25-red) | ![0.0%](https://img.shields.io/badge/0.0%25-red) |

**Total :** 317 500 tests — **936 417 échecs** d'assertions.

---

> **Note :** Le tableau décompose les résultats entre adresses **paires** (colonne *Paires*) et **impaires** (colonne *Impaire*) via l'analyse automatisée du trafic mémoire.  
> La détection des accès impairs couvre les lectures/écritures 16/32 bits sur adresse impaire et le PC impair après exécution.  
> Les opcodes marqués *Complet* en *Paires* passent 100% de leurs tests sur adresses paires ; les échecs résiduels sont soit des bugs réels sur adresses paires (score &lt; 100%), soit des cas d'adresse impaire (colonne *Impaire*).  
> Les instructions de saut (JMP, JSR, BSR) ne déclenchent pas d'accès mémoire à la cible impaire dans notre CPU (le PC est aligné post-exécution par `decode.zig`), donc tous leurs tests sont classés *Paires*.

## Résultats des tests de timing

51 opcodes testés via `zig build test-cpu-timing -Doptimize=ReleaseFast`, comparant les cycles émulés aux cycles attendus (M68000PM).

**51/51 ✅ — 0 échec**

| Catégorie | Instructions | Résultat |
|------------|-------------|----------|
| Instructions registre | ADD, SUB, CMP, MOVE, NEG, NOT, CLR, TST, EXT, SWAP, NOP, MOVEQ, MOVEA | ✅ |
| Instructions de contrôle | RTS, RTE, RTR, STOP, TRAP, TRAPV, ILLEGAL, LINK, UNLK | ✅ |
| Instructions mémoire | LEA, PEA, JMP, JSR | ✅ |
| Flags et SR | ANDI/ORI/EORI CCR/SR, MOVE SR | ✅ |
| Arithmétique complexe | NBCD, TAS, MULU, DIVU, DIVS, CHK | ✅ |
| ADDX/SUBX registre | ADDX, SUBX | ✅ |
---

## Fonctionnalités implémentées

### Architecture du CPU
- **Registres** D0–D7, A0–A7, PC, SR, USP/SSP
- **Mode Superviseur / Utilisateur** avec bascule via `sr.s` et sauvegarde USP/SSP
- **Registre d'état (SR)** : champs T, S, I2–I0, X, N, Z, V, C avec getters/setters
- **Reset** : lit SSP (0x000000) et PC (0x000004), SR = 0x2700
- **Interruptions** : `checkInterrupt`, `dispatchInterrupt`, sauvegarde PC+SR, mise à jour IPL, appel vecteur `(24+level)*4`
- **Exceptions** : fonction `exception` empilant PC+SR, passage superviseur, lecture vecteur
- **STOP / HALT** : retourne 4 cycles si le CPU est arrêté
- **Vérification alignement PC** : force alignement mot si PC impair

### Décodeur et modes d'adressage
- **Décodeur complet** : 12 blocs d'opcodes couvrant tout le jeu d'instructions 68000
- **Modes d'adressage** : Dn, An, (An), (An)+, -(An), (d16,An), (d8,An,Xn), absolute short/long, (d16,PC), (d8,PC,Xn), immédiat
- **Helpers arithmétiques/mémoire** : `addSigned`, `signExtend*`, `isNegative`, `readMem/writeMem`, `mergeValue`, `updateNZ`
