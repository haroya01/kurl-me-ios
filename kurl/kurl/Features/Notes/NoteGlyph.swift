//
//  NoteGlyph.swift
//  kurl
//

import SwiftUI

/// 노트 반응 아이콘(좋아요·답글·리포스트·공유) — 웹(short-link-frontend note-glyph.tsx)과 같은 경로.
/// 24 격자, 선 1.8, 둥근 끝. 한쪽을 고치면 다른 쪽도 고친다.
enum NoteGlyph {
    case heart, reply, repost, share

    fileprivate var paths: [String] {
        switch self {
        case .heart: [
            "M12 20.3C11.7 20.3 11.4 20.2 11.15 20.02C7.1 17.15 3.75 14.1 3.75 9.9C3.75 7.2 5.8 5.25 8.3 5.25C9.8 5.25 11.15 6 12 7.2C12.85 6 14.2 5.25 15.7 5.25C18.2 5.25 20.25 7.2 20.25 9.9C20.25 14.1 16.9 17.15 12.85 20.02C12.6 20.2 12.3 20.3 12 20.3Z",
        ]
        case .reply: [
            "M12 4.1C16.25 4.1 19.7 7.55 19.7 11.8C19.7 16.05 16.25 19.5 12 19.5C10.82 19.5 9.7 19.24 8.7 18.77L4.6 19.95L5.72 16.1C4.82 14.9 4.3 13.4 4.3 11.8C4.3 7.55 7.75 4.1 12 4.1Z",
        ]
        case .repost: [
            "M4.75 11.25V9.75C4.75 7.82 6.32 6.25 8.25 6.25H19.25",
            "M16.5 3.5L19.25 6.25L16.5 9",
            "M19.25 12.75V14.25C19.25 16.18 17.68 17.75 15.75 17.75H4.75",
            "M7.5 20.5L4.75 17.75L7.5 15",
        ]
        case .share: [
            "M20.25 12L4.35 4.6L7.1 12L4.35 19.4Z",
            "M7.1 12H12.9",
        ]
        }
    }
}

struct NoteGlyphView: View {
    let glyph: NoteGlyph
    var active = false
    var size: CGFloat = 17

    var body: some View {
        let width = (active && glyph == .repost ? 2.2 : 1.8) * size / 24
        ZStack {
            ForEach(glyph.paths, id: \.self) { d in
                if active && glyph == .heart {
                    SVGPathShape(d: d).fill()
                }
                SVGPathShape(d: d)
                    .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 절대 좌표 M·L·H·V·C·Z 만 읽는 24 격자 SVG 경로. 아이콘 경로는 이 명령만 쓴다.
private struct SVGPathShape: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        SVGPathShape.parsed(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / 24, y: rect.height / 24))
    }

    private static func parsed(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var token = ""

        func flushToken() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        func apply() {
            switch command {
            case "M":
                while numbers.count >= 2 {
                    current = CGPoint(x: numbers[0], y: numbers[1])
                    path.move(to: current)
                    numbers.removeFirst(2)
                    command = "L"
                }
            case "L":
                while numbers.count >= 2 {
                    current = CGPoint(x: numbers[0], y: numbers[1])
                    path.addLine(to: current)
                    numbers.removeFirst(2)
                }
            case "H":
                while let x = numbers.first {
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                    numbers.removeFirst()
                }
            case "V":
                while let y = numbers.first {
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                    numbers.removeFirst()
                }
            case "C":
                while numbers.count >= 6 {
                    current = CGPoint(x: numbers[4], y: numbers[5])
                    path.addCurve(
                        to: current,
                        control1: CGPoint(x: numbers[0], y: numbers[1]),
                        control2: CGPoint(x: numbers[2], y: numbers[3]))
                    numbers.removeFirst(6)
                }
            case "Z":
                path.closeSubpath()
            default:
                numbers.removeAll()
            }
        }

        for character in d {
            if character.isLetter {
                flushToken()
                apply()
                command = character
                if character == "Z" { apply() }
            } else if character == " " || character == "," {
                flushToken()
            } else if character == "-", !token.isEmpty {
                flushToken()
                token = "-"
            } else {
                token.append(character)
            }
        }
        flushToken()
        apply()
        return path
    }
}
