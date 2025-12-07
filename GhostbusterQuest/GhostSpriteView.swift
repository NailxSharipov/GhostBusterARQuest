//
//  GhostSpriteView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 11.12.2025.
//

import SwiftUI
import CoreGraphics

struct GhostSpriteView: View {
    @State private var mouthOpen = false

    private let bodyPath = """
    m 244.59599,693.47395 c -1.0177,-65.06198 51.60877,-120.62193 63.48136,-184.59958 15.05067,-81.10342 -32.72014,-176.05643 8.8462,-247.30617 31.37882,-53.78709 96.96059,-97.76113 159.23158,-97.69558 63.50634,0.0668 130.50662,44.93145 162.18032,99.9754 37.80685,65.70244 -2.82092,152.03352 5.89747,227.33397 10.21457,88.22281 117.50815,198.65984 54.13348,260.87925 -26.86783,26.37804 -73.448,-33.34439 -110.15942,-24.98064 -40.10245,9.13629 -55.63088,73.55924 -96.63928,76.72 -47.60813,3.66946 -76.76636,-70.78429 -124.51568,-70.82253 -33.89262,-0.0271 -56.58225,61.63463 -88.462,50.12847 -30.05636,-10.84808 -33.49428,-57.68236 -33.99403,-89.63259 z
    """

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 1024

            ZStack {
                GhostBodyShape(svgPath: bodyPath)
                    .fill(Color.white.opacity(0.95))
                .overlay(
                        GhostBodyShape(svgPath: bodyPath)
                            .stroke(Color.black, lineWidth: 38.3335 * scale)
                    )

                // Eyes
                EyeView(center: CGPoint(x: 410.267, y: 331.401), rx: 29.638386, ry: 41.653946, scale: scale)
                EyeView(center: CGPoint(x: 522.41229, y: 329.79901), rx: 29.638386, ry: 41.653946, scale: scale)

                // Mouth
                MouthView(center: CGPoint(x: 464.97693, y: 459.96613), rx: 45.260113, ry: 57.275669, scale: scale, open: mouthOpen)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                Task {
                    await animateMouth()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func animateMouth() async {
        while true {
            let wait = Double.random(in: 1.8...3.5)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    mouthOpen = true
                }
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    mouthOpen = false
                }
            }
        }
    }
}

private struct GhostBodyShape: Shape {
    let svgPath: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cgPath = CGPath.make(fromSVGPath: svgPath)
        let scale = min(rect.width, rect.height) / 1024
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        if let scaled = cgPath.copy(using: &transform) {
            path.addPath(Path(scaled))
        }
        return path
    }
}

private struct EyeView: View {
    let center: CGPoint
    let rx: CGFloat
    let ry: CGFloat
    let scale: CGFloat

    var body: some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: rx * 2 * scale, height: ry * 2 * scale)
            .position(x: center.x * scale, y: center.y * scale)
    }
}

private struct MouthView: View {
    let center: CGPoint
    let rx: CGFloat
    let ry: CGFloat
    let scale: CGFloat
    let open: Bool

    var body: some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: rx * 2 * scale, height: ry * 2 * scale)
            .scaleEffect(y: open ? 1.25 : 0.7, anchor: .center)
            .position(x: center.x * scale, y: center.y * scale)
    }
}

private extension CGPath {
    static func make(fromSVGPath d: String) -> CGPath {
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")

        let path = CGMutablePath()
        var current = CGPoint.zero
        var startPoint = CGPoint.zero
        var currentCommand: Character?

        while !scanner.isAtEnd {
            if let cmd = scanner.scanCharacter(), cmd.isLetter {
                currentCommand = cmd
            } else if currentCommand == nil {
                _ = scanner.scanUpToCharacters(from: CharacterSet.letters)
                continue
            } else if let backIndex = scanner.string.index(scanner.currentIndex, offsetBy: -1, limitedBy: scanner.string.startIndex) {
                scanner.currentIndex = backIndex
            }

            guard let cmd = currentCommand else { break }

            switch cmd {
            case "m", "M":
                if let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let point = cmd.isLowercase ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.move(to: point)
                    current = point
                    startPoint = point
                    currentCommand = cmd == "m" ? "l" : "L"
                }
            case "c", "C":
                while true {
                    guard
                        let x1 = scanner.scanDouble(),
                        let y1 = scanner.scanDouble(),
                        let x2 = scanner.scanDouble(),
                        let y2 = scanner.scanDouble(),
                        let x = scanner.scanDouble(),
                        let y = scanner.scanDouble()
                    else { break }

                    let cp1 = cmd.isLowercase ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                    let cp2 = cmd.isLowercase ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                    let end = cmd.isLowercase ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)

                    path.addCurve(to: end, control1: cp1, control2: cp2)
                    current = end
                }
            case "l", "L":
                while true {
                    guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { break }
                    let point = cmd.isLowercase ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addLine(to: point)
                    current = point
                }
            case "z", "Z":
                path.closeSubpath()
                current = startPoint
            default:
                break
            }
        }

        return path
    }
}

private extension Scanner {
    func scanDouble() -> Double? {
        var value: Double = 0
        if scanDouble(&value) {
            return value
        }
        return nil
    }
}

struct GhostSpriteView_Previews: PreviewProvider {
    static var previews: some View {
        GhostSpriteView()
            .frame(width: 260, height: 260)
            .padding()
            .background(Color.black.opacity(0.9))
            .preferredColorScheme(.dark)
    }
}
