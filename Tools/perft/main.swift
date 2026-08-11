//
//  main.swift
//  Scan — development tool, not part of any app target
//
//  Standalone deep-perft verifier for the chess engine. Run it with
//  `Tools/run-perft.sh`; see that script's header for why this exists as
//  a separate binary rather than as part of the XCTest suite.
//
//  The filename is load-bearing: Swift only permits top-level statements
//  in a file called `main.swift`, which is why this sits in its own
//  directory rather than beside the shell script as `perft-main.swift`.
//
//  It compiles the engine sources straight from `Scan/Chess/` with
//  optimisation, so it verifies exactly the code the app ships — there is
//  no second copy of the engine to drift.
//
//  Exit status is 0 when every count matches, 1 otherwise, so CI can gate
//  on it.
//

import Foundation

/// Count leaf nodes of the legal-move tree.
///
/// Bulk-counts at depth 1 (the move list length is the answer), matching
/// `ChessEngineTests.perft` so the two agree by construction.
func perft(_ position: inout ChessPosition, _ depth: Int) -> Int {
    let moves = ChessMoveGenerator.generateLegal(&position)
    if depth <= 1 { return depth == 0 ? 1 : moves.count }
    var nodes = 0
    for index in 0..<moves.count {
        let move = moves[index]
        let undo = position.make(move)
        nodes += perft(&position, depth - 1)
        position.unmake(move, undo)
    }
    return nodes
}

/// Per-root-move node counts, for when a total is wrong and you need to
/// know *which* move's subtree is off. Compare against any reference
/// engine's `divide` output.
func perftDivide(_ position: inout ChessPosition, _ depth: Int) -> [(String, Int)] {
    guard depth >= 1 else { return [] }
    let moves = ChessMoveGenerator.generateLegal(&position)
    var out: [(String, Int)] = []
    for index in 0..<moves.count {
        let move = moves[index]
        let undo = position.make(move)
        out.append((move.uci, depth == 1 ? 1 : perft(&position, depth - 1)))
        position.unmake(move, undo)
    }
    return out.sorted { $0.0 < $1.0 }
}

/// The standard six positions and their published counts. These numbers
/// are not ours — they are the values every engine agrees on, which is
/// the entire reason perft is a useful test. Do not "fix" one to match
/// the code.
let cases: [(name: String, fen: String, expected: [Int])] = [
    ("startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
     [20, 400, 8902, 197_281, 4_865_609, 119_060_324]),
    ("kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
     [48, 2039, 97_862, 4_085_603, 193_690_690]),
    ("position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
     [14, 191, 2812, 43_238, 674_624, 11_030_083]),
    ("position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
     [6, 264, 9467, 422_333, 15_833_292]),
    ("position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
     [44, 1486, 62_379, 2_103_487, 89_941_194]),
    ("position6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
     [46, 2079, 89_890, 3_894_594, 164_075_551]),
]

// `divide <fen> <depth>` — the debugging mode.
let arguments = CommandLine.arguments
if arguments.count >= 4, arguments[1] == "divide" {
    guard var position = ChessPosition(fen: arguments[2]), let depth = Int(arguments[3]) else {
        FileHandle.standardError.write(Data("usage: perft divide <fen> <depth>\n".utf8))
        exit(2)
    }
    var total = 0
    for (move, nodes) in perftDivide(&position, depth) {
        print("\(move): \(nodes)")
        total += nodes
    }
    print("total: \(total)")
    exit(0)
}

// Default mode: verify every case. An optional argument caps the depth,
// e.g. `run-perft.sh 4` for a quick pass.
let maximumDepth = arguments.count > 1 ? (Int(arguments[1]) ?? Int.max) : Int.max

var failures = 0
var totalNodes = 0
let started = Date()

for testCase in cases {
    guard var position = ChessPosition(fen: testCase.fen) else {
        print("FAIL \(testCase.name): could not parse FEN")
        failures += 1
        continue
    }
    for (offset, expected) in testCase.expected.enumerated() {
        let depth = offset + 1
        if depth > maximumDepth { break }

        let startedDepth = Date()
        let actual = perft(&position, depth)
        let elapsed = Date().timeIntervalSince(startedDepth)
        totalNodes += actual

        if actual == expected {
            let rate = elapsed > 0.01
                ? String(format: "  %.0fM nodes/s", Double(actual) / elapsed / 1_000_000)
                : ""
            print(String(format: "ok   %@ perft(%d) = %d  [%.2fs]%@",
                         testCase.name, depth, actual, elapsed, rate))
        } else {
            print("FAIL \(testCase.name) perft(\(depth)) = \(actual), expected \(expected)")
            print("     re-run with: Tools/run-perft.sh divide \"\(testCase.fen)\" \(depth)")
            failures += 1
            // Deeper counts are meaningless once one is wrong.
            break
        }
    }
}

print("---")
print(String(format: "%d nodes, %d failure(s), %.1fs total",
             totalNodes, failures, Date().timeIntervalSince(started)))
exit(failures == 0 ? 0 : 1)
