import UIKit
import SwiftUI

final class CircuitSymbolRenderer {

    static let shared = CircuitSymbolRenderer()

    private init() {}

    // MARK: - Render Symbol to UIImage

    func render(symbol: CircuitSymbolType,
                strokeColor: UIColor = .label,
                lineWidth: CGFloat = 3.0,
                targetSize: CGSize = CGSize(width: 240, height: 160)) -> UIImage {

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(strokeColor.cgColor)
            cg.setFillColor(strokeColor.cgColor)
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let rect = CGRect(origin: .zero, size: targetSize)
            let midX = rect.midX
            let midY = rect.midY

            switch symbol {
            // MARK: - Passives
            case .resistorDIN:
                renderResistorDIN(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .resistorUS:
                renderResistorUS(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .potentiometer:
                renderPotentiometer(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .capacitor:
                renderCapacitor(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth, polarized: false)
            case .capacitorPolarized:
                renderCapacitor(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth, polarized: true)
            case .capacitorVariable:
                renderCapacitorVariable(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .inductor:
                renderInductor(cg: cg, rect: rect, midX: midX, midY: midY, ironCore: false, lineWidth: lineWidth)
            case .inductorIronCore:
                renderInductor(cg: cg, rect: rect, midX: midX, midY: midY, ironCore: true, lineWidth: lineWidth)
            case .transformer:
                renderTransformer(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .fuse:
                renderFuse(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .ptcResistor:
                renderTempResistor(cg: cg, rect: rect, midX: midX, midY: midY, label: "+t°", strokeColor: strokeColor, lineWidth: lineWidth)
            case .ntcResistor:
                renderTempResistor(cg: cg, rect: rect, midX: midX, midY: midY, label: "-t°", strokeColor: strokeColor, lineWidth: lineWidth)
            case .ldrResistor:
                renderLDR(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)

            // MARK: - Sources
            case .dcSource:
                renderDCSource(cg: cg, rect: rect, midX: midX, midY: midY, strokeColor: strokeColor, lineWidth: lineWidth)
            case .batterySingle:
                renderBattery(cg: cg, rect: rect, midX: midX, midY: midY, cells: 1, strokeColor: strokeColor, lineWidth: lineWidth)
            case .batteryMulti:
                renderBattery(cg: cg, rect: rect, midX: midX, midY: midY, cells: 3, strokeColor: strokeColor, lineWidth: lineWidth)
            case .acSource:
                renderACSource(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .currentSource:
                renderCurrentSource(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .groundGND:
                renderGroundGND(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .earthGroundPE:
                renderEarthPE(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .terminalPin:
                renderTerminalPin(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)

            // MARK: - Semiconductors
            case .diode:
                renderDiode(cg: cg, rect: rect, midX: midX, midY: midY, type: .standard, lineWidth: lineWidth)
            case .zenerDiode:
                renderDiode(cg: cg, rect: rect, midX: midX, midY: midY, type: .zener, lineWidth: lineWidth)
            case .schottkyDiode:
                renderDiode(cg: cg, rect: rect, midX: midX, midY: midY, type: .schottky, lineWidth: lineWidth)
            case .led:
                renderDiode(cg: cg, rect: rect, midX: midX, midY: midY, type: .led, lineWidth: lineWidth)
            case .photodiode:
                renderDiode(cg: cg, rect: rect, midX: midX, midY: midY, type: .photo, lineWidth: lineWidth)
            case .npnTransistor:
                renderTransistor(cg: cg, rect: rect, midX: midX, midY: midY, isNPN: true, lineWidth: lineWidth)
            case .pnpTransistor:
                renderTransistor(cg: cg, rect: rect, midX: midX, midY: midY, isNPN: false, lineWidth: lineWidth)
            case .nMosfet:
                renderMOSFET(cg: cg, rect: rect, midX: midX, midY: midY, isNChannel: true, lineWidth: lineWidth)
            case .pMosfet:
                renderMOSFET(cg: cg, rect: rect, midX: midX, midY: midY, isNChannel: false, lineWidth: lineWidth)
            case .opAmp:
                renderOpAmp(cg: cg, rect: rect, midX: midX, midY: midY, strokeColor: strokeColor, lineWidth: lineWidth)

            // MARK: - Switches
            case .switchNormallyOpen:
                renderSwitch(cg: cg, rect: rect, midX: midX, midY: midY, state: .open, lineWidth: lineWidth)
            case .switchNormallyClose:
                renderSwitch(cg: cg, rect: rect, midX: midX, midY: midY, state: .closed, lineWidth: lineWidth)
            case .switchToggleSPDT:
                renderSwitchSPDT(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .relayContact:
                renderRelay(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .junctionPoint:
                renderJunction(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .bridgeNoConnection:
                renderBridge(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)

            // MARK: - Measurement
            case .voltmeter:
                renderMeter(cg: cg, rect: rect, midX: midX, midY: midY, letter: "V", strokeColor: strokeColor, lineWidth: lineWidth)
            case .amperemeter:
                renderMeter(cg: cg, rect: rect, midX: midX, midY: midY, letter: "A", strokeColor: strokeColor, lineWidth: lineWidth)
            case .ohmmeter:
                renderMeter(cg: cg, rect: rect, midX: midX, midY: midY, letter: "Ω", strokeColor: strokeColor, lineWidth: lineWidth)
            case .oscilloscope:
                renderOscilloscope(cg: cg, rect: rect, midX: midX, midY: midY, strokeColor: strokeColor, lineWidth: lineWidth)
            case .lightBulb:
                renderLamp(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
            case .motor:
                renderMeter(cg: cg, rect: rect, midX: midX, midY: midY, letter: "M", strokeColor: strokeColor, lineWidth: lineWidth)
            case .generator:
                renderMeter(cg: cg, rect: rect, midX: midX, midY: midY, letter: "G", strokeColor: strokeColor, lineWidth: lineWidth)

            // MARK: - Logic
            case .logicAND:
                renderLogicGate(cg: cg, rect: rect, midX: midX, midY: midY, symbol: "&", inverted: false, strokeColor: strokeColor, lineWidth: lineWidth)
            case .logicOR:
                renderLogicGate(cg: cg, rect: rect, midX: midX, midY: midY, symbol: "≥1", inverted: false, strokeColor: strokeColor, lineWidth: lineWidth)
            case .logicNOT:
                renderLogicGate(cg: cg, rect: rect, midX: midX, midY: midY, symbol: "1", inverted: true, strokeColor: strokeColor, lineWidth: lineWidth)
            case .logicNAND:
                renderLogicGate(cg: cg, rect: rect, midX: midX, midY: midY, symbol: "&", inverted: true, strokeColor: strokeColor, lineWidth: lineWidth)
            case .logicNOR:
                renderLogicGate(cg: cg, rect: rect, midX: midX, midY: midY, symbol: "≥1", inverted: true, strokeColor: strokeColor, lineWidth: lineWidth)
            case .logicXOR:
                renderLogicGate(cg: cg, rect: rect, midX: midX, midY: midY, symbol: "=1", inverted: false, strokeColor: strokeColor, lineWidth: lineWidth)

            // MARK: - Circuits
            case .circuitSimpleLamp:
                renderCircuitSimpleLamp(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitSeriesR:
                renderCircuitSeries(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitParallelR:
                renderCircuitParallel(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitVoltageDiv:
                renderCircuitVoltageDivider(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitWheatstone:
                renderCircuitWheatstone(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitRCTlowPass:
                renderCircuitRCLowPass(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitRCHighPass:
                renderCircuitRCHighPass(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitGraetzBridge:
                renderCircuitGraetz(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitOpAmpInvert:
                renderCircuitOpAmpInverting(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitOpAmpNonInv:
                renderCircuitOpAmpNonInverting(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            case .circuitLedDriver:
                renderCircuitLEDDriver(cg: cg, rect: rect, strokeColor: strokeColor, lineWidth: lineWidth)
            }
        }
    }

    // MARK: - Helper Methods

    private func drawText(_ text: String, at point: CGPoint, color: UIColor, font: UIFont) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let textRect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        str.draw(in: textRect)
    }

    // MARK: - Render Implementations

    private func renderResistorDIN(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let rw: CGFloat = 80
        let rh: CGFloat = 30
        let rBox = CGRect(x: midX - rw/2, y: midY - rh/2, width: rw, height: rh)

        cg.stroke(rBox)
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: rBox.minX, y: midY))
        cg.move(to: CGPoint(x: rBox.maxX, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    private func renderResistorUS(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let startX = rect.minX + 25
        let endX = rect.maxX - 25
        let span = (endX - startX) / 8

        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: startX, y: midY))
        cg.addLine(to: CGPoint(x: startX + span, y: midY - 22))
        cg.addLine(to: CGPoint(x: startX + span * 2, y: midY + 22))
        cg.addLine(to: CGPoint(x: startX + span * 3, y: midY - 22))
        cg.addLine(to: CGPoint(x: startX + span * 4, y: midY + 22))
        cg.addLine(to: CGPoint(x: startX + span * 5, y: midY - 22))
        cg.addLine(to: CGPoint(x: startX + span * 6, y: midY + 22))
        cg.addLine(to: CGPoint(x: startX + span * 7, y: midY - 22))
        cg.addLine(to: CGPoint(x: endX, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    private func renderPotentiometer(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        renderResistorDIN(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
        // Arrow pointing from bottom left to center
        cg.move(to: CGPoint(x: midX - 35, y: midY + 45))
        cg.addLine(to: CGPoint(x: midX + 10, y: midY + 5))
        cg.strokePath()
        // Arrowhead
        cg.move(to: CGPoint(x: midX + 10, y: midY + 5))
        cg.addLine(to: CGPoint(x: midX - 2, y: midY + 6))
        cg.move(to: CGPoint(x: midX + 10, y: midY + 5))
        cg.addLine(to: CGPoint(x: midX + 6, y: midY + 18))
        cg.strokePath()
    }

    private func renderCapacitor(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat, polarized: Bool) {
        let plateH: CGFloat = 60
        let gap: CGFloat = 16

        // Left plate
        cg.move(to: CGPoint(x: midX - gap/2, y: midY - plateH/2))
        cg.addLine(to: CGPoint(x: midX - gap/2, y: midY + plateH/2))

        // Right plate
        if polarized {
            // Curved negative plate for electrolytic capacitor
            let path = UIBezierPath()
            path.move(to: CGPoint(x: midX + gap/2, y: midY - plateH/2))
            path.addQuadCurve(to: CGPoint(x: midX + gap/2, y: midY + plateH/2),
                              controlPoint: CGPoint(x: midX + gap/2 + 18, y: midY))
            cg.addPath(path.cgPath)
        } else {
            cg.move(to: CGPoint(x: midX + gap/2, y: midY - plateH/2))
            cg.addLine(to: CGPoint(x: midX + gap/2, y: midY + plateH/2))
        }

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - gap/2, y: midY))
        cg.move(to: CGPoint(x: midX + gap/2, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        if polarized {
            drawText("+", at: CGPoint(x: midX - gap/2 - 16, y: midY - 24), color: .label, font: .boldSystemFont(ofSize: 18))
        }
    }

    private func renderCapacitorVariable(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        renderCapacitor(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth, polarized: false)
        // Diagonal arrow across plates
        cg.move(to: CGPoint(x: midX - 35, y: midY + 40))
        cg.addLine(to: CGPoint(x: midX + 35, y: midY - 40))
        cg.addLine(to: CGPoint(x: midX + 22, y: midY - 38))
        cg.move(to: CGPoint(x: midX + 35, y: midY - 40))
        cg.addLine(to: CGPoint(x: midX + 33, y: midY - 25))
        cg.strokePath()
    }

    private func renderInductor(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, ironCore: Bool, lineWidth: CGFloat) {
        let loops = 4
        let loopRadius: CGFloat = 13
        let startX = midX - CGFloat(loops) * loopRadius
        let endX = midX + CGFloat(loops) * loopRadius

        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: startX, y: midY))

        for i in 0..<loops {
            let cx = startX + CGFloat(i * 2 + 1) * loopRadius
            cg.addArc(center: CGPoint(x: cx, y: midY), radius: loopRadius, startAngle: .pi, endAngle: 0, clockwise: false)
        }

        cg.move(to: CGPoint(x: endX, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        if ironCore {
            let coreY = midY - loopRadius - 6
            cg.move(to: CGPoint(x: startX, y: coreY))
            cg.addLine(to: CGPoint(x: endX, y: coreY))
            cg.move(to: CGPoint(x: startX, y: coreY - 4))
            cg.addLine(to: CGPoint(x: endX, y: coreY - 4))
            cg.strokePath()
        }
    }

    private func renderTransformer(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let r: CGFloat = 12
        let loops = 3
        let h = CGFloat(loops * 2) * r
        let startY = midY - h/2

        // Primary coil (left)
        for i in 0..<loops {
            let cy = startY + CGFloat(i * 2 + 1) * r
            cg.addArc(center: CGPoint(x: midX - 25, y: cy), radius: r, startAngle: .pi/2, endAngle: -.pi/2, clockwise: false)
        }
        // Secondary coil (right)
        for i in 0..<loops {
            let cy = startY + CGFloat(i * 2 + 1) * r
            cg.addArc(center: CGPoint(x: midX + 25, y: cy), radius: r, startAngle: -.pi/2, endAngle: .pi/2, clockwise: false)
        }

        // Core lines
        cg.move(to: CGPoint(x: midX - 3, y: startY - 6))
        cg.addLine(to: CGPoint(x: midX - 3, y: startY + h + 6))
        cg.move(to: CGPoint(x: midX + 3, y: startY - 6))
        cg.addLine(to: CGPoint(x: midX + 3, y: startY + h + 6))

        // Leads
        cg.move(to: CGPoint(x: midX - 25, y: startY))
        cg.addLine(to: CGPoint(x: rect.minX + 15, y: startY))
        cg.move(to: CGPoint(x: midX - 25, y: startY + h))
        cg.addLine(to: CGPoint(x: rect.minX + 15, y: startY + h))

        cg.move(to: CGPoint(x: midX + 25, y: startY))
        cg.addLine(to: CGPoint(x: rect.maxX - 15, y: startY))
        cg.move(to: CGPoint(x: midX + 25, y: startY + h))
        cg.addLine(to: CGPoint(x: rect.maxX - 15, y: startY + h))
        cg.strokePath()
    }

    private func renderFuse(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let fw: CGFloat = 75
        let fh: CGFloat = 28
        let rBox = CGRect(x: midX - fw/2, y: midY - fh/2, width: fw, height: fh)
        cg.stroke(rBox)

        // Continuous wire running right through the fuse body
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    private func renderTempResistor(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, label: String, strokeColor: UIColor, lineWidth: CGFloat) {
        renderResistorDIN(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
        // Angled temperature probe indicator
        cg.move(to: CGPoint(x: midX - 35, y: midY + 28))
        cg.addLine(to: CGPoint(x: midX - 15, y: midY + 28))
        cg.addLine(to: CGPoint(x: midX + 35, y: midY - 28))
        cg.strokePath()
        drawText(label, at: CGPoint(x: midX + 42, y: midY - 26), color: strokeColor, font: .boldSystemFont(ofSize: 14))
    }

    private func renderLDR(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        renderResistorDIN(cg: cg, rect: rect, midX: midX, midY: midY, lineWidth: lineWidth)
        // Two light arrows incoming from top left
        for i in [0, 1] {
            let off: CGFloat = CGFloat(i) * 16
            let p1 = CGPoint(x: midX - 25 + off, y: midY - 45)
            let p2 = CGPoint(x: midX - 10 + off, y: midY - 22)
            cg.move(to: p1)
            cg.addLine(to: p2)
            cg.addLine(to: CGPoint(x: p2.x - 7, y: p2.y - 2))
            cg.move(to: p2)
            cg.addLine(to: CGPoint(x: p2.x - 1, y: p2.y - 8))
        }
        cg.strokePath()
    }

    // MARK: - Sources

    private func renderDCSource(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, strokeColor: UIColor, lineWidth: CGFloat) {
        let r: CGFloat = 34
        cg.strokeEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))

        // Horizontal partition line (DIN DC source)
        cg.move(to: CGPoint(x: midX - r, y: midY))
        cg.addLine(to: CGPoint(x: midX + r, y: midY))

        // Leads
        cg.move(to: CGPoint(x: midX, y: midY - r))
        cg.addLine(to: CGPoint(x: midX, y: rect.minY + 10))
        cg.move(to: CGPoint(x: midX, y: midY + r))
        cg.addLine(to: CGPoint(x: midX, y: rect.maxY - 10))
        cg.strokePath()

        drawText("+", at: CGPoint(x: midX + 22, y: midY - 16), color: strokeColor, font: .boldSystemFont(ofSize: 16))
        drawText("-", at: CGPoint(x: midX + 22, y: midY + 16), color: strokeColor, font: .boldSystemFont(ofSize: 18))
    }

    private func renderBattery(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, cells: Int, strokeColor: UIColor, lineWidth: CGFloat) {
        let longH: CGFloat = 60
        let shortH: CGFloat = 28
        let gap: CGFloat = 12

        let totalW = CGFloat(cells) * gap * 2
        var curX = midX - totalW/2

        for _ in 0..<cells {
            // Long thin line (+)
            cg.setLineWidth(lineWidth)
            cg.move(to: CGPoint(x: curX, y: midY - longH/2))
            cg.addLine(to: CGPoint(x: curX, y: midY + longH/2))
            cg.strokePath()

            curX += gap

            // Short thick line (-)
            cg.setLineWidth(lineWidth * 2.2)
            cg.move(to: CGPoint(x: curX, y: midY - shortH/2))
            cg.addLine(to: CGPoint(x: curX, y: midY + shortH/2))
            cg.strokePath()

            curX += gap
        }

        cg.setLineWidth(lineWidth)
        // Leads
        let leftX = midX - totalW/2
        let rightX = curX - gap
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: leftX, y: midY))
        cg.move(to: CGPoint(x: rightX, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        drawText("+", at: CGPoint(x: leftX - 12, y: midY - 20), color: strokeColor, font: .boldSystemFont(ofSize: 16))
        drawText("-", at: CGPoint(x: rightX + 12, y: midY - 16), color: strokeColor, font: .boldSystemFont(ofSize: 18))
    }

    private func renderACSource(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let r: CGFloat = 34
        cg.strokeEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))

        // Sine wave in center
        let path = UIBezierPath()
        let sw: CGFloat = 36
        path.move(to: CGPoint(x: midX - sw/2, y: midY))
        path.addCurve(to: CGPoint(x: midX, y: midY),
                      controlPoint1: CGPoint(x: midX - sw/4, y: midY - 18),
                      controlPoint2: CGPoint(x: midX - sw/4, y: midY - 18))
        path.addCurve(to: CGPoint(x: midX + sw/2, y: midY),
                      controlPoint1: CGPoint(x: midX + sw/4, y: midY + 18),
                      controlPoint2: CGPoint(x: midX + sw/4, y: midY + 18))
        cg.addPath(path.cgPath)

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - r, y: midY))
        cg.move(to: CGPoint(x: midX + r, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    private func renderCurrentSource(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let r: CGFloat = 34
        cg.strokeEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))

        // Arrow through center
        cg.move(to: CGPoint(x: midX - 22, y: midY))
        cg.addLine(to: CGPoint(x: midX + 22, y: midY))
        cg.addLine(to: CGPoint(x: midX + 12, y: midY - 8))
        cg.move(to: CGPoint(x: midX + 22, y: midY))
        cg.addLine(to: CGPoint(x: midX + 12, y: midY + 8))

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - r, y: midY))
        cg.move(to: CGPoint(x: midX + r, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    private func renderGroundGND(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        cg.move(to: CGPoint(x: midX, y: rect.minY + 20))
        cg.addLine(to: CGPoint(x: midX, y: midY))

        let widths: [CGFloat] = [48, 30, 14]
        for (i, w) in widths.enumerated() {
            let y = midY + CGFloat(i * 10)
            cg.move(to: CGPoint(x: midX - w/2, y: y))
            cg.addLine(to: CGPoint(x: midX + w/2, y: y))
        }
        cg.strokePath()
    }

    private func renderEarthPE(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        cg.move(to: CGPoint(x: midX, y: rect.minY + 20))
        cg.addLine(to: CGPoint(x: midX, y: midY))

        let w: CGFloat = 50
        cg.move(to: CGPoint(x: midX - w/2, y: midY))
        cg.addLine(to: CGPoint(x: midX + w/2, y: midY))

        // 3 angled hash marks
        for i in [-1, 0, 1] {
            let x = midX + CGFloat(i) * 14
            cg.move(to: CGPoint(x: x, y: midY))
            cg.addLine(to: CGPoint(x: x - 10, y: midY + 16))
        }
        cg.strokePath()
    }

    private func renderTerminalPin(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let r: CGFloat = 7
        cg.strokeEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))
        cg.move(to: CGPoint(x: rect.minX + 15, y: midY))
        cg.addLine(to: CGPoint(x: midX - r, y: midY))
        cg.strokePath()
    }

    // MARK: - Semiconductors

    private func renderDiode(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, type: DiodeType, lineWidth: CGFloat) {
        let dw: CGFloat = 36
        let dh: CGFloat = 40

        // Triangle (Anode)
        cg.move(to: CGPoint(x: midX - dw/2, y: midY - dh/2))
        cg.addLine(to: CGPoint(x: midX + dw/2, y: midY))
        cg.addLine(to: CGPoint(x: midX - dw/2, y: midY + dh/2))
        cg.closePath()
        cg.strokePath()

        // Kathode bar
        let kx = midX + dw/2
        switch type {
        case .standard, .led, .photo:
            cg.move(to: CGPoint(x: kx, y: midY - dh/2))
            cg.addLine(to: CGPoint(x: kx, y: midY + dh/2))
        case .zener:
            cg.move(to: CGPoint(x: kx - 8, y: midY - dh/2))
            cg.addLine(to: CGPoint(x: kx, y: midY - dh/2))
            cg.addLine(to: CGPoint(x: kx, y: midY + dh/2))
            cg.addLine(to: CGPoint(x: kx + 8, y: midY + dh/2))
        case .schottky:
            cg.move(to: CGPoint(x: kx - 8, y: midY - dh/2 + 8))
            cg.addLine(to: CGPoint(x: kx - 8, y: midY - dh/2))
            cg.addLine(to: CGPoint(x: kx, y: midY - dh/2))
            cg.addLine(to: CGPoint(x: kx, y: midY + dh/2))
            cg.addLine(to: CGPoint(x: kx + 8, y: midY + dh/2))
            cg.addLine(to: CGPoint(x: kx + 8, y: midY + dh/2 - 8))
        }

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - dw/2, y: midY))
        cg.move(to: CGPoint(x: kx, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        if type == .led {
            // 2 outgoing emission arrows
            for i in [0, 1] {
                let off: CGFloat = CGFloat(i) * 14
                let p1 = CGPoint(x: midX - 6 + off, y: midY - 24)
                let p2 = CGPoint(x: midX + 10 + off, y: midY - 44)
                cg.move(to: p1)
                cg.addLine(to: p2)
                cg.addLine(to: CGPoint(x: p2.x - 7, y: p2.y + 1))
                cg.move(to: p2)
                cg.addLine(to: CGPoint(x: p2.x - 1, y: p2.y + 7))
            }
            cg.strokePath()
        } else if type == .photo {
            // 2 incoming arrows
            for i in [0, 1] {
                let off: CGFloat = CGFloat(i) * 14
                let p1 = CGPoint(x: midX - 18 + off, y: midY - 44)
                let p2 = CGPoint(x: midX - 2 + off, y: midY - 24)
                cg.move(to: p1)
                cg.addLine(to: p2)
                cg.addLine(to: CGPoint(x: p2.x - 7, y: p2.y - 1))
                cg.move(to: p2)
                cg.addLine(to: CGPoint(x: p2.x - 1, y: p2.y - 7))
            }
            cg.strokePath()
        }
    }

    private enum DiodeType {
        case standard, zener, schottky, led, photo
    }

    private func renderTransistor(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, isNPN: Bool, lineWidth: CGFloat) {
        // Base vertical bar
        let bx = midX - 10
        let bh: CGFloat = 46
        cg.setLineWidth(lineWidth * 1.5)
        cg.move(to: CGPoint(x: bx, y: midY - bh/2))
        cg.addLine(to: CGPoint(x: bx, y: midY + bh/2))
        cg.strokePath()

        cg.setLineWidth(lineWidth)
        // Base lead
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: bx, y: midY))

        // Collector (top right)
        cg.move(to: CGPoint(x: bx, y: midY - 14))
        cg.addLine(to: CGPoint(x: midX + 26, y: midY - 34))
        cg.addLine(to: CGPoint(x: midX + 26, y: rect.minY + 12))

        // Emitter (bottom right)
        let ex = midX + 26
        let ey = midY + 34
        cg.move(to: CGPoint(x: bx, y: midY + 14))
        cg.addLine(to: CGPoint(x: ex, y: ey))
        cg.addLine(to: CGPoint(x: ex, y: rect.maxY - 12))
        cg.strokePath()

        // Emitter arrow
        if isNPN {
            // Arrow pointing away from base on emitter
            let ax = bx + (ex - bx) * 0.72
            let ay = (midY + 14) + (ey - (midY + 14)) * 0.72
            cg.move(to: CGPoint(x: ax, y: ay))
            cg.addLine(to: CGPoint(x: ax - 11, y: ay - 2))
            cg.move(to: CGPoint(x: ax, y: ay))
            cg.addLine(to: CGPoint(x: ax - 3, y: ay - 11))
        } else {
            // PNP: Arrow pointing towards base on emitter
            let ax = bx + (ex - bx) * 0.40
            let ay = (midY + 14) + (ey - (midY + 14)) * 0.40
            cg.move(to: CGPoint(x: ax, y: ay))
            cg.addLine(to: CGPoint(x: ax + 11, y: ay + 2))
            cg.move(to: CGPoint(x: ax, y: ay))
            cg.addLine(to: CGPoint(x: ax + 3, y: ay + 11))
        }
        cg.strokePath()

        // Transistor circle boundary
        let r: CGFloat = 42
        cg.strokeEllipse(in: CGRect(x: midX + 4 - r, y: midY - r, width: r*2, height: r*2))
    }

    private func renderMOSFET(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, isNChannel: Bool, lineWidth: CGFloat) {
        let gx = midX - 16
        let chX = midX - 6
        let h: CGFloat = 50

        // Gate line
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY + 16))
        cg.addLine(to: CGPoint(x: gx, y: midY + 16))
        cg.addLine(to: CGPoint(x: gx, y: midY - h/2))
        cg.addLine(to: CGPoint(x: gx, y: midY + h/2))

        // Channel (3 segments: Drain, Bulk, Source)
        let segH: CGFloat = 12
        let yOffsets: [CGFloat] = [-18, 0, 18]
        for yOff in yOffsets {
            cg.move(to: CGPoint(x: chX, y: midY + yOff - segH/2))
            cg.addLine(to: CGPoint(x: chX, y: midY + yOff + segH/2))
        }

        // Drain lead (top)
        cg.move(to: CGPoint(x: chX, y: midY - 18))
        cg.addLine(to: CGPoint(x: midX + 25, y: midY - 18))
        cg.addLine(to: CGPoint(x: midX + 25, y: rect.minY + 10))

        // Source lead (bottom)
        cg.move(to: CGPoint(x: chX, y: midY + 18))
        cg.addLine(to: CGPoint(x: midX + 25, y: midY + 18))
        cg.addLine(to: CGPoint(x: midX + 25, y: rect.maxY - 10))

        // Bulk / Substrate center lead connected to source
        cg.move(to: CGPoint(x: chX, y: midY))
        cg.addLine(to: CGPoint(x: midX + 25, y: midY))
        cg.addLine(to: CGPoint(x: midX + 25, y: midY + 18))
        cg.strokePath()

        // Substrate arrow
        let ax = chX + 12
        if isNChannel {
            // Arrow pointing inwards
            cg.move(to: CGPoint(x: chX + 4, y: midY))
            cg.addLine(to: CGPoint(x: ax, y: midY - 6))
            cg.move(to: CGPoint(x: chX + 4, y: midY))
            cg.addLine(to: CGPoint(x: ax, y: midY + 6))
        } else {
            // Arrow pointing outwards
            cg.move(to: CGPoint(x: ax, y: midY))
            cg.addLine(to: CGPoint(x: chX + 4, y: midY - 6))
            cg.move(to: CGPoint(x: ax, y: midY))
            cg.addLine(to: CGPoint(x: chX + 4, y: midY + 6))
        }
        cg.strokePath()
    }

    private func renderOpAmp(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, strokeColor: UIColor, lineWidth: CGFloat) {
        let tw: CGFloat = 80
        let th: CGFloat = 90
        let leftX = midX - tw/2
        let rightX = midX + tw/2

        // Main triangle
        cg.move(to: CGPoint(x: leftX, y: midY - th/2))
        cg.addLine(to: CGPoint(x: rightX, y: midY))
        cg.addLine(to: CGPoint(x: leftX, y: midY + th/2))
        cg.closePath()
        cg.strokePath()

        // Inverting (-) & Non-inverting (+) input leads
        let inY1 = midY - 22
        let inY2 = midY + 22
        cg.move(to: CGPoint(x: rect.minX + 10, y: inY1))
        cg.addLine(to: CGPoint(x: leftX, y: inY1))
        cg.move(to: CGPoint(x: rect.minX + 10, y: inY2))
        cg.addLine(to: CGPoint(x: leftX, y: inY2))

        // Output lead
        cg.move(to: CGPoint(x: rightX, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        drawText("-", at: CGPoint(x: leftX + 14, y: inY1), color: strokeColor, font: .boldSystemFont(ofSize: 18))
        drawText("+", at: CGPoint(x: leftX + 14, y: inY2), color: strokeColor, font: .boldSystemFont(ofSize: 16))
    }

    // MARK: - Switches

    private func renderSwitch(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, state: SwitchState, lineWidth: CGFloat) {
        let r: CGFloat = 4.5
        let d: CGFloat = 36

        // Contact terminals
        cg.strokeEllipse(in: CGRect(x: midX - d - r, y: midY - r, width: r*2, height: r*2))
        cg.strokeEllipse(in: CGRect(x: midX + d - r, y: midY - r, width: r*2, height: r*2))

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - d - r, y: midY))
        cg.move(to: CGPoint(x: midX + d + r, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))

        // Blade
        let bladeStart = CGPoint(x: midX - d + r, y: midY)
        if state == .open {
            cg.move(to: bladeStart)
            cg.addLine(to: CGPoint(x: midX + d - 4, y: midY - 26))
        } else {
            cg.move(to: bladeStart)
            cg.addLine(to: CGPoint(x: midX + d - r, y: midY))
        }
        cg.strokePath()
    }

    private enum SwitchState { case open, closed }

    private func renderSwitchSPDT(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let r: CGFloat = 4
        let inX = midX - 35
        let outX = midX + 35
        let outY1 = midY - 24
        let outY2 = midY + 24

        // 3 Terminal circles
        cg.strokeEllipse(in: CGRect(x: inX - r, y: midY - r, width: r*2, height: r*2))
        cg.strokeEllipse(in: CGRect(x: outX - r, y: outY1 - r, width: r*2, height: r*2))
        cg.strokeEllipse(in: CGRect(x: outX - r, y: outY2 - r, width: r*2, height: r*2))

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: inX - r, y: midY))
        cg.move(to: CGPoint(x: outX + r, y: outY1))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: outY1))
        cg.move(to: CGPoint(x: outX + r, y: outY2))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: outY2))

        // Blade connected to inX pointing to upper terminal
        cg.move(to: CGPoint(x: inX + r, y: midY))
        cg.addLine(to: CGPoint(x: outX - r - 3, y: outY1 + 5))
        cg.strokePath()
    }

    private func renderRelay(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        // Coil rectangle on left
        let cw: CGFloat = 34
        let ch: CGFloat = 60
        let cBox = CGRect(x: midX - cw - 15, y: midY - ch/2, width: cw, height: ch)
        cg.stroke(cBox)
        cg.move(to: CGPoint(x: cBox.minX, y: cBox.minY))
        cg.addLine(to: CGPoint(x: cBox.maxX, y: cBox.maxY))

        // Contact switch on right
        let swX = midX + 25
        let r: CGFloat = 3.5
        cg.strokeEllipse(in: CGRect(x: swX - r, y: midY - 24 - r, width: r*2, height: r*2))
        cg.strokeEllipse(in: CGRect(x: swX - r, y: midY + 24 - r, width: r*2, height: r*2))
        cg.move(to: CGPoint(x: swX, y: midY - 24 + r))
        cg.addLine(to: CGPoint(x: swX + 16, y: midY + 12))

        // Dashed coupling line
        cg.setLineDash(phase: 0, lengths: [4, 4])
        cg.move(to: CGPoint(x: cBox.maxX, y: midY))
        cg.addLine(to: CGPoint(x: swX + 8, y: midY))
        cg.strokePath()
        cg.setLineDash(phase: 0, lengths: []) // Reset dash
    }

    private func renderJunction(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.move(to: CGPoint(x: midX, y: rect.minY + 10))
        cg.addLine(to: CGPoint(x: midX, y: rect.maxY - 10))
        cg.strokePath()

        // Filled dot
        let r: CGFloat = 6.5
        cg.fillEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))
    }

    private func renderBridge(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        // Horizontal line
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        // Vertical line jumping over horizontal line with semi-circle bridge
        let r: CGFloat = 10
        cg.move(to: CGPoint(x: midX, y: rect.minY + 10))
        cg.addLine(to: CGPoint(x: midX, y: midY - r))
        cg.addArc(center: CGPoint(x: midX, y: midY), radius: r, startAngle: -.pi/2, endAngle: .pi/2, clockwise: true)
        cg.addLine(to: CGPoint(x: midX, y: rect.maxY - 10))
        cg.strokePath()
    }

    // MARK: - Measurement & Loads

    private func renderMeter(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, letter: String, strokeColor: UIColor, lineWidth: CGFloat) {
        let r: CGFloat = 34
        cg.strokeEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - r, y: midY))
        cg.move(to: CGPoint(x: midX + r, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()

        drawText(letter, at: CGPoint(x: midX, y: midY), color: strokeColor, font: .boldSystemFont(ofSize: 26))
    }

    private func renderOscilloscope(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, strokeColor: UIColor, lineWidth: CGFloat) {
        let bw: CGFloat = 76
        let bh: CGFloat = 58
        let rBox = CGRect(x: midX - bw/2, y: midY - bh/2, width: bw, height: bh)
        cg.stroke(rBox)

        // Wave inside screen
        let path = UIBezierPath()
        let w = bw * 0.7
        path.move(to: CGPoint(x: midX - w/2, y: midY))
        path.addCurve(to: CGPoint(x: midX, y: midY), controlPoint1: CGPoint(x: midX - w/4, y: midY - 14), controlPoint2: CGPoint(x: midX - w/4, y: midY - 14))
        path.addCurve(to: CGPoint(x: midX + w/2, y: midY), controlPoint1: CGPoint(x: midX + w/4, y: midY + 14), controlPoint2: CGPoint(x: midX + w/4, y: midY + 14))
        cg.addPath(path.cgPath)

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: rBox.minX, y: midY))
        cg.move(to: CGPoint(x: rBox.maxX, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    private func renderLamp(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, lineWidth: CGFloat) {
        let r: CGFloat = 32
        cg.strokeEllipse(in: CGRect(x: midX - r, y: midY - r, width: r*2, height: r*2))

        // Diagonal cross
        let d = r * 0.7071
        cg.move(to: CGPoint(x: midX - d, y: midY - d))
        cg.addLine(to: CGPoint(x: midX + d, y: midY + d))
        cg.move(to: CGPoint(x: midX - d, y: midY + d))
        cg.addLine(to: CGPoint(x: midX + d, y: midY - d))

        // Leads
        cg.move(to: CGPoint(x: rect.minX + 10, y: midY))
        cg.addLine(to: CGPoint(x: midX - r, y: midY))
        cg.move(to: CGPoint(x: midX + r, y: midY))
        cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        cg.strokePath()
    }

    // MARK: - Logic Gates (DIN EN 60617 / IEC)

    private func renderLogicGate(cg: CGContext, rect: CGRect, midX: CGFloat, midY: CGFloat, symbol: String, inverted: Bool, strokeColor: UIColor, lineWidth: CGFloat) {
        let gw: CGFloat = 64
        let gh: CGFloat = 76
        let box = CGRect(x: midX - gw/2, y: midY - gh/2, width: gw, height: gh)
        cg.stroke(box)

        // Inputs (left)
        let inY1 = midY - 18
        let inY2 = midY + 18
        cg.move(to: CGPoint(x: rect.minX + 10, y: inY1))
        cg.addLine(to: CGPoint(x: box.minX, y: inY1))
        cg.move(to: CGPoint(x: rect.minX + 10, y: inY2))
        cg.addLine(to: CGPoint(x: box.minX, y: inY2))

        // Output (right)
        if inverted {
            let ir: CGFloat = 4.5
            cg.strokeEllipse(in: CGRect(x: box.maxX, y: midY - ir, width: ir*2, height: ir*2))
            cg.move(to: CGPoint(x: box.maxX + ir*2, y: midY))
            cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        } else {
            cg.move(to: CGPoint(x: box.maxX, y: midY))
            cg.addLine(to: CGPoint(x: rect.maxX - 10, y: midY))
        }
        cg.strokePath()

        drawText(symbol, at: CGPoint(x: box.midX, y: box.minY + 22), color: strokeColor, font: .boldSystemFont(ofSize: 20))
    }

    // MARK: - Circuit Templates (Stromkreise)

    private func renderCircuitSimpleLamp(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let padX: CGFloat = 30
        let padY: CGFloat = 25
        let circuitRect = rect.insetBy(dx: padX, dy: padY)

        // Closed loop rectangle
        cg.stroke(circuitRect)

        // Draw DC source on left side
        let sourceY = circuitRect.midY
        let srcR: CGFloat = 22
        cg.clear(CGRect(x: circuitRect.minX - srcR - 4, y: sourceY - srcR - 4, width: (srcR + 4)*2, height: (srcR + 4)*2))
        cg.strokeEllipse(in: CGRect(x: circuitRect.minX - srcR, y: sourceY - srcR, width: srcR*2, height: srcR*2))
        drawText("U", at: CGPoint(x: circuitRect.minX - srcR - 16, y: sourceY), color: strokeColor, font: .boldSystemFont(ofSize: 14))

        // Draw Switch on top branch
        let swX = circuitRect.midX
        cg.clear(CGRect(x: swX - 25, y: circuitRect.minY - 12, width: 50, height: 24))
        cg.move(to: CGPoint(x: swX - 18, y: circuitRect.minY))
        cg.addLine(to: CGPoint(x: swX + 16, y: circuitRect.minY - 14))
        cg.strokePath()
        drawText("S1", at: CGPoint(x: swX, y: circuitRect.minY - 22), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // Draw Lamp on right branch
        let lampY = circuitRect.midY
        let lampR: CGFloat = 20
        cg.clear(CGRect(x: circuitRect.maxX - lampR - 4, y: lampY - lampR - 4, width: (lampR + 4)*2, height: (lampR + 4)*2))
        cg.strokeEllipse(in: CGRect(x: circuitRect.maxX - lampR, y: lampY - lampR, width: lampR*2, height: lampR*2))
        let ld = lampR * 0.7071
        cg.move(to: CGPoint(x: circuitRect.maxX - ld, y: lampY - ld))
        cg.addLine(to: CGPoint(x: circuitRect.maxX + ld, y: lampY + ld))
        cg.move(to: CGPoint(x: circuitRect.maxX - ld, y: lampY + ld))
        cg.addLine(to: CGPoint(x: circuitRect.maxX + ld, y: lampY - ld))
        cg.strokePath()
        drawText("E1", at: CGPoint(x: circuitRect.maxX + 26, y: lampY), color: strokeColor, font: .boldSystemFont(ofSize: 14))
    }

    private func renderCircuitSeries(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let circuitRect = rect.insetBy(dx: 30, dy: 25)
        cg.stroke(circuitRect)

        // Source left
        let srcR: CGFloat = 22
        cg.clear(CGRect(x: circuitRect.minX - srcR - 4, y: circuitRect.midY - srcR - 4, width: (srcR + 4)*2, height: (srcR + 4)*2))
        cg.strokeEllipse(in: CGRect(x: circuitRect.minX - srcR, y: circuitRect.midY - srcR, width: srcR*2, height: srcR*2))
        drawText("U0", at: CGPoint(x: circuitRect.minX - srcR - 16, y: circuitRect.midY), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // R1 & R2 on top wire
        let rw: CGFloat = 46
        let rh: CGFloat = 18
        let r1X = circuitRect.minX + circuitRect.width * 0.35
        let r2X = circuitRect.minX + circuitRect.width * 0.75
        let topY = circuitRect.minY

        cg.clear(CGRect(x: r1X - rw/2 - 2, y: topY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: r1X - rw/2, y: topY - rh/2, width: rw, height: rh))
        drawText("R1", at: CGPoint(x: r1X, y: topY - rh/2 - 12), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        cg.clear(CGRect(x: r2X - rw/2 - 2, y: topY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: r2X - rw/2, y: topY - rh/2, width: rw, height: rh))
        drawText("R2", at: CGPoint(x: r2X, y: topY - rh/2 - 12), color: strokeColor, font: .boldSystemFont(ofSize: 13))
    }

    private func renderCircuitParallel(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let leftX = rect.minX + 30
        let topY = rect.minY + 25
        let botY = rect.maxY - 25
        let branch1X = rect.minX + (rect.width) * 0.52
        let branch2X = rect.minX + (rect.width) * 0.85

        // Outer box up to branch 2
        cg.stroke(CGRect(x: leftX, y: topY, width: branch2X - leftX, height: botY - topY))

        // Middle vertical branch
        cg.move(to: CGPoint(x: branch1X, y: topY))
        cg.addLine(to: CGPoint(x: branch1X, y: botY))
        cg.strokePath()

        // Junction dots
        cg.setFillColor(strokeColor.cgColor)
        for x in [branch1X, branch2X] {
            cg.fillEllipse(in: CGRect(x: x - 4.5, y: topY - 4.5, width: 9, height: 9))
            cg.fillEllipse(in: CGRect(x: x - 4.5, y: botY - 4.5, width: 9, height: 9))
        }

        // Source on left
        let srcR: CGFloat = 20
        cg.clear(CGRect(x: leftX - srcR - 3, y: (topY+botY)/2 - srcR - 3, width: (srcR+3)*2, height: (srcR+3)*2))
        cg.strokeEllipse(in: CGRect(x: leftX - srcR, y: (topY+botY)/2 - srcR, width: srcR*2, height: srcR*2))
        drawText("U", at: CGPoint(x: leftX - srcR - 14, y: (topY+botY)/2), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // R1 in branch 1
        let rw: CGFloat = 20
        let rh: CGFloat = 46
        let midY = (topY + botY) / 2
        cg.clear(CGRect(x: branch1X - rw/2 - 2, y: midY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: branch1X - rw/2, y: midY - rh/2, width: rw, height: rh))
        drawText("R1", at: CGPoint(x: branch1X + rw/2 + 14, y: midY), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // R2 in branch 2
        cg.clear(CGRect(x: branch2X - rw/2 - 2, y: midY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: branch2X - rw/2, y: midY - rh/2, width: rw, height: rh))
        drawText("R2", at: CGPoint(x: branch2X + rw/2 + 14, y: midY), color: strokeColor, font: .boldSystemFont(ofSize: 13))
    }

    private func renderCircuitVoltageDivider(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let x = rect.midX - 25
        let topY = rect.minY + 20
        let botY = rect.maxY - 20
        let midY = (topY + botY) / 2

        // Vertical backbone
        cg.move(to: CGPoint(x: x, y: topY))
        cg.addLine(to: CGPoint(x: x, y: botY))
        cg.strokePath()

        // Resistors R1 & R2
        let rw: CGFloat = 22
        let rh: CGFloat = 44
        let r1Y = topY + (midY - topY)/2
        let r2Y = midY + (botY - midY)/2

        cg.clear(CGRect(x: x - rw/2 - 2, y: r1Y - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: x - rw/2, y: r1Y - rh/2, width: rw, height: rh))
        drawText("R1", at: CGPoint(x: x - rw/2 - 16, y: r1Y), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        cg.clear(CGRect(x: x - rw/2 - 2, y: r2Y - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: x - rw/2, y: r2Y - rh/2, width: rw, height: rh))
        drawText("R2", at: CGPoint(x: x - rw/2 - 16, y: r2Y), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // Vout tap from center
        let outX = rect.maxX - 25
        cg.move(to: CGPoint(x: x, y: midY))
        cg.addLine(to: CGPoint(x: outX, y: midY))
        cg.move(to: CGPoint(x: x, y: botY))
        cg.addLine(to: CGPoint(x: outX, y: botY))
        cg.strokePath()

        // Tap nodes
        cg.setFillColor(strokeColor.cgColor)
        cg.fillEllipse(in: CGRect(x: x - 4, y: midY - 4, width: 8, height: 8))
        cg.fillEllipse(in: CGRect(x: x - 4, y: botY - 4, width: 8, height: 8))

        drawText("Vin", at: CGPoint(x: x, y: topY - 12), color: strokeColor, font: .boldSystemFont(ofSize: 13))
        drawText("Vout", at: CGPoint(x: outX + 18, y: midY), color: strokeColor, font: .boldSystemFont(ofSize: 13))
        drawText("GND", at: CGPoint(x: outX + 18, y: botY), color: strokeColor, font: .boldSystemFont(ofSize: 13))
    }

    private func renderCircuitWheatstone(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let cx = rect.midX
        let cy = rect.midY
        let dx: CGFloat = 55
        let dy: CGFloat = 45

        let topP = CGPoint(x: cx, y: cy - dy)
        let botP = CGPoint(x: cx, y: cy + dy)
        let leftP = CGPoint(x: cx - dx, y: cy)
        let rightP = CGPoint(x: cx + dx, y: cy)

        // Rhombus wires
        cg.move(to: topP); cg.addLine(to: leftP)
        cg.move(to: leftP); cg.addLine(to: botP)
        cg.move(to: botP); cg.addLine(to: rightP)
        cg.move(to: rightP); cg.addLine(to: topP)
        cg.strokePath()

        // Bridge voltmeter in center
        cg.move(to: leftP); cg.addLine(to: rightP)
        cg.strokePath()
        let vmR: CGFloat = 16
        cg.clear(CGRect(x: cx - vmR, y: cy - vmR, width: vmR*2, height: vmR*2))
        cg.strokeEllipse(in: CGRect(x: cx - vmR, y: cy - vmR, width: vmR*2, height: vmR*2))
        drawText("V", at: CGPoint(x: cx, y: cy), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // Nodes
        cg.setFillColor(strokeColor.cgColor)
        for p in [topP, botP, leftP, rightP] {
            cg.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }

        // External power leads
        cg.move(to: CGPoint(x: topP.x, y: topP.y - 20))
        cg.addLine(to: topP)
        cg.move(to: botP)
        cg.addLine(to: CGPoint(x: botP.x, y: botP.y + 20))
        cg.strokePath()

        drawText("+U0", at: CGPoint(x: topP.x + 18, y: topP.y - 20), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("-U0", at: CGPoint(x: botP.x + 18, y: botP.y + 20), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("R1", at: CGPoint(x: (topP.x+leftP.x)/2 - 14, y: (topP.y+leftP.y)/2 - 10), color: strokeColor, font: .systemFont(ofSize: 11, weight: .bold))
        drawText("R2", at: CGPoint(x: (topP.x+rightP.x)/2 + 14, y: (topP.y+rightP.y)/2 - 10), color: strokeColor, font: .systemFont(ofSize: 11, weight: .bold))
        drawText("R3", at: CGPoint(x: (botP.x+leftP.x)/2 - 14, y: (botP.y+leftP.y)/2 + 10), color: strokeColor, font: .systemFont(ofSize: 11, weight: .bold))
        drawText("R4", at: CGPoint(x: (botP.x+rightP.x)/2 + 14, y: (botP.y+rightP.y)/2 + 10), color: strokeColor, font: .systemFont(ofSize: 11, weight: .bold))
    }

    private func renderCircuitRCLowPass(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let inX = rect.minX + 25
        let outX = rect.maxX - 25
        let topY = rect.minY + 30
        let botY = rect.maxY - 25
        let capX = rect.midX + 25

        // Top line
        cg.move(to: CGPoint(x: inX, y: topY))
        cg.addLine(to: CGPoint(x: outX, y: topY))
        // Bottom ground line
        cg.move(to: CGPoint(x: inX, y: botY))
        cg.addLine(to: CGPoint(x: outX, y: botY))
        // Vertical capacitor branch
        cg.move(to: CGPoint(x: capX, y: topY))
        cg.addLine(to: CGPoint(x: capX, y: botY))
        cg.strokePath()

        // Resistor in top line
        let rX = rect.midX - 35
        let rw: CGFloat = 50
        let rh: CGFloat = 20
        cg.clear(CGRect(x: rX - rw/2 - 2, y: topY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: rX - rw/2, y: topY - rh/2, width: rw, height: rh))
        drawText("R", at: CGPoint(x: rX, y: topY - rh/2 - 12), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // Capacitor in vertical branch
        let capY = (topY + botY) / 2
        let ch: CGFloat = 12
        let cw: CGFloat = 34
        cg.clear(CGRect(x: capX - cw/2, y: capY - ch/2, width: cw, height: ch))
        cg.move(to: CGPoint(x: capX - cw/2, y: capY - ch/2))
        cg.addLine(to: CGPoint(x: capX + cw/2, y: capY - ch/2))
        cg.move(to: CGPoint(x: capX - cw/2, y: capY + ch/2))
        cg.addLine(to: CGPoint(x: capX + cw/2, y: capY + ch/2))
        cg.strokePath()
        drawText("C", at: CGPoint(x: capX + cw/2 + 12, y: capY), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        drawText("U_in", at: CGPoint(x: inX - 10, y: (topY+botY)/2), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("U_out", at: CGPoint(x: outX + 10, y: (topY+botY)/2), color: strokeColor, font: .boldSystemFont(ofSize: 12))
    }

    private func renderCircuitRCHighPass(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let inX = rect.minX + 25
        let outX = rect.maxX - 25
        let topY = rect.minY + 30
        let botY = rect.maxY - 25
        let rBranchX = rect.midX + 25

        // Top line
        cg.move(to: CGPoint(x: inX, y: topY))
        cg.addLine(to: CGPoint(x: outX, y: topY))
        // Bottom ground line
        cg.move(to: CGPoint(x: inX, y: botY))
        cg.addLine(to: CGPoint(x: outX, y: botY))
        // Vertical resistor branch
        cg.move(to: CGPoint(x: rBranchX, y: topY))
        cg.addLine(to: CGPoint(x: rBranchX, y: botY))
        cg.strokePath()

        // Capacitor in top line
        let capX = rect.midX - 35
        let ch: CGFloat = 34
        let cw: CGFloat = 12
        cg.clear(CGRect(x: capX - cw/2, y: topY - ch/2, width: cw, height: ch))
        cg.move(to: CGPoint(x: capX - cw/2, y: topY - ch/2))
        cg.addLine(to: CGPoint(x: capX - cw/2, y: topY + ch/2))
        cg.move(to: CGPoint(x: capX + cw/2, y: topY - ch/2))
        cg.addLine(to: CGPoint(x: capX + cw/2, y: topY + ch/2))
        cg.strokePath()
        drawText("C", at: CGPoint(x: capX, y: topY - ch/2 - 10), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // Resistor in vertical branch
        let rY = (topY + botY) / 2
        let rw: CGFloat = 20
        let rh: CGFloat = 46
        cg.clear(CGRect(x: rBranchX - rw/2 - 2, y: rY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: rBranchX - rw/2, y: rY - rh/2, width: rw, height: rh))
        drawText("R", at: CGPoint(x: rBranchX + rw/2 + 14, y: rY), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        drawText("U_in", at: CGPoint(x: inX - 10, y: (topY+botY)/2), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("U_out", at: CGPoint(x: outX + 10, y: (topY+botY)/2), color: strokeColor, font: .boldSystemFont(ofSize: 12))
    }

    private func renderCircuitGraetz(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let cx = rect.midX - 25
        let cy = rect.midY
        let d: CGFloat = 40

        let topP = CGPoint(x: cx, y: cy - d)
        let botP = CGPoint(x: cx, y: cy + d)
        let leftP = CGPoint(x: cx - d, y: cy)
        let rightP = CGPoint(x: cx + d, y: cy)

        // AC input leads to Left and Right
        cg.move(to: CGPoint(x: rect.minX + 15, y: cy - 20))
        cg.addLine(to: CGPoint(x: cx - d - 15, y: cy - 20))
        cg.addLine(to: leftP)

        cg.move(to: CGPoint(x: rect.minX + 15, y: cy + 20))
        cg.addLine(to: CGPoint(x: cx - d - 15, y: cy + 20))
        cg.addLine(to: rightP)

        // Bridge branches
        cg.move(to: leftP); cg.addLine(to: topP)
        cg.move(to: leftP); cg.addLine(to: botP)
        cg.move(to: rightP); cg.addLine(to: topP)
        cg.move(to: rightP); cg.addLine(to: botP)
        cg.strokePath()

        // DC Output leads to right
        let outX = rect.maxX - 20
        cg.move(to: topP); cg.addLine(to: CGPoint(x: outX, y: topP.y))
        cg.move(to: botP); cg.addLine(to: CGPoint(x: outX, y: botP.y))
        cg.strokePath()

        // Load resistor + capacitor
        let loadX = outX - 30
        cg.move(to: CGPoint(x: loadX, y: topP.y))
        cg.addLine(to: CGPoint(x: loadX, y: botP.y))
        cg.strokePath()

        let rw: CGFloat = 18
        let rh: CGFloat = 40
        cg.clear(CGRect(x: loadX - rw/2 - 2, y: cy - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: loadX - rw/2, y: cy - rh/2, width: rw, height: rh))
        drawText("RL", at: CGPoint(x: loadX + rw/2 + 12, y: cy), color: strokeColor, font: .boldSystemFont(ofSize: 11))

        drawText("AC ~", at: CGPoint(x: rect.minX + 32, y: cy), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("+ DC", at: CGPoint(x: outX + 16, y: topP.y), color: strokeColor, font: .boldSystemFont(ofSize: 11))
        drawText("- DC", at: CGPoint(x: outX + 16, y: botP.y), color: strokeColor, font: .boldSystemFont(ofSize: 11))
    }

    private func renderCircuitOpAmpInverting(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let cx = rect.midX + 10
        let cy = rect.midY

        // Op-Amp
        let tw: CGFloat = 65
        let th: CGFloat = 75
        let opL = cx - tw/2
        let opR = cx + tw/2
        cg.move(to: CGPoint(x: opL, y: cy - th/2))
        cg.addLine(to: CGPoint(x: opR, y: cy))
        cg.addLine(to: CGPoint(x: opL, y: cy + th/2))
        cg.closePath()
        cg.strokePath()

        let inY1 = cy - 18 // Inverting (-)
        let inY2 = cy + 18 // Non-inverting (+)
        drawText("-", at: CGPoint(x: opL + 12, y: inY1), color: strokeColor, font: .boldSystemFont(ofSize: 16))
        drawText("+", at: CGPoint(x: opL + 12, y: inY2), color: strokeColor, font: .boldSystemFont(ofSize: 14))

        // Ground on (+) input
        cg.move(to: CGPoint(x: opL, y: inY2))
        cg.addLine(to: CGPoint(x: opL - 18, y: inY2))
        cg.addLine(to: CGPoint(x: opL - 18, y: inY2 + 14))
        cg.strokePath()
        let gndY = inY2 + 14
        for (i, w) in [24, 14, 6].enumerated() {
            let gy = gndY + CGFloat(i * 4)
            cg.move(to: CGPoint(x: opL - 18 - CGFloat(w)/2, y: gy))
            cg.addLine(to: CGPoint(x: opL - 18 + CGFloat(w)/2, y: gy))
        }
        cg.strokePath()

        // Input wire with R1
        let inX = rect.minX + 20
        let nodeX = opL - 25
        cg.move(to: CGPoint(x: inX, y: inY1))
        cg.addLine(to: CGPoint(x: opL, y: inY1))
        cg.strokePath()

        let r1X = (inX + nodeX) / 2
        let rw: CGFloat = 40
        let rh: CGFloat = 16
        cg.clear(CGRect(x: r1X - rw/2 - 2, y: inY1 - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: r1X - rw/2, y: inY1 - rh/2, width: rw, height: rh))
        drawText("R1", at: CGPoint(x: r1X, y: inY1 - rh/2 - 10), color: strokeColor, font: .boldSystemFont(ofSize: 11))

        // Output lead
        let outX = rect.maxX - 20
        cg.move(to: CGPoint(x: opR, y: cy))
        cg.addLine(to: CGPoint(x: outX, y: cy))
        cg.strokePath()

        // Feedback loop with Rf over top
        let fbY = cy - th/2 - 14
        let fbNodeR = opR + 25
        cg.move(to: CGPoint(x: nodeX, y: inY1))
        cg.addLine(to: CGPoint(x: nodeX, y: fbY))
        cg.addLine(to: CGPoint(x: fbNodeR, y: fbY))
        cg.addLine(to: CGPoint(x: fbNodeR, y: cy))
        cg.strokePath()

        // Rf in feedback wire
        let rfX = cx
        cg.clear(CGRect(x: rfX - rw/2 - 2, y: fbY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: rfX - rw/2, y: fbY - rh/2, width: rw, height: rh))
        drawText("Rf", at: CGPoint(x: rfX, y: fbY - rh/2 - 10), color: strokeColor, font: .boldSystemFont(ofSize: 11))

        // Nodes
        cg.setFillColor(strokeColor.cgColor)
        cg.fillEllipse(in: CGRect(x: nodeX - 3.5, y: inY1 - 3.5, width: 7, height: 7))
        cg.fillEllipse(in: CGRect(x: fbNodeR - 3.5, y: cy - 3.5, width: 7, height: 7))

        drawText("U_in", at: CGPoint(x: inX - 10, y: inY1), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("U_out", at: CGPoint(x: outX + 14, y: cy), color: strokeColor, font: .boldSystemFont(ofSize: 12))
    }

    private func renderCircuitOpAmpNonInverting(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let cx = rect.midX + 10
        let cy = rect.midY

        // Op-Amp
        let tw: CGFloat = 65
        let th: CGFloat = 75
        let opL = cx - tw/2
        let opR = cx + tw/2
        cg.move(to: CGPoint(x: opL, y: cy - th/2))
        cg.addLine(to: CGPoint(x: opR, y: cy))
        cg.addLine(to: CGPoint(x: opL, y: cy + th/2))
        cg.closePath()
        cg.strokePath()

        let inY1 = cy - 18 // Inverting (-)
        let inY2 = cy + 18 // Non-inverting (+)
        drawText("-", at: CGPoint(x: opL + 12, y: inY1), color: strokeColor, font: .boldSystemFont(ofSize: 16))
        drawText("+", at: CGPoint(x: opL + 12, y: inY2), color: strokeColor, font: .boldSystemFont(ofSize: 14))

        // Input wire straight to (+)
        let inX = rect.minX + 20
        cg.move(to: CGPoint(x: inX, y: inY2))
        cg.addLine(to: CGPoint(x: opL, y: inY2))
        cg.strokePath()

        // Output lead
        let outX = rect.maxX - 20
        cg.move(to: CGPoint(x: opR, y: cy))
        cg.addLine(to: CGPoint(x: outX, y: cy))
        cg.strokePath()

        // Feedback loop from output to (-) input with divider R1 / R2
        let fbY = cy - th/2 - 14
        let fbNodeR = opR + 25
        let nodeX = opL - 25
        cg.move(to: CGPoint(x: nodeX, y: inY1))
        cg.addLine(to: CGPoint(x: nodeX, y: fbY))
        cg.addLine(to: CGPoint(x: fbNodeR, y: fbY))
        cg.addLine(to: CGPoint(x: fbNodeR, y: cy))
        cg.strokePath()

        // Rf in loop
        let rw: CGFloat = 38
        let rh: CGFloat = 16
        let rfX = cx
        cg.clear(CGRect(x: rfX - rw/2 - 2, y: fbY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: rfX - rw/2, y: fbY - rh/2, width: rw, height: rh))
        drawText("R2", at: CGPoint(x: rfX, y: fbY - rh/2 - 10), color: strokeColor, font: .boldSystemFont(ofSize: 11))

        // R1 to ground from nodeX
        cg.move(to: CGPoint(x: nodeX, y: inY1))
        cg.addLine(to: CGPoint(x: nodeX, y: cy + 30))
        cg.strokePath()

        let r1Y = inY1 + 18
        cg.clear(CGRect(x: nodeX - rh/2 - 2, y: r1Y - rw/2 - 2, width: rh + 4, height: rw + 4))
        cg.stroke(CGRect(x: nodeX - rh/2, y: r1Y - rw/2, width: rh, height: rw))
        drawText("R1", at: CGPoint(x: nodeX - rh/2 - 12, y: r1Y), color: strokeColor, font: .boldSystemFont(ofSize: 11))

        drawText("U_in", at: CGPoint(x: inX - 10, y: inY2), color: strokeColor, font: .boldSystemFont(ofSize: 12))
        drawText("U_out", at: CGPoint(x: outX + 14, y: cy), color: strokeColor, font: .boldSystemFont(ofSize: 12))
    }

    private func renderCircuitLEDDriver(cg: CGContext, rect: CGRect, strokeColor: UIColor, lineWidth: CGFloat) {
        let circuitRect = rect.insetBy(dx: 30, dy: 25)
        cg.stroke(circuitRect)

        // DC Source on left
        let srcR: CGFloat = 20
        cg.clear(CGRect(x: circuitRect.minX - srcR - 4, y: circuitRect.midY - srcR - 4, width: (srcR+4)*2, height: (srcR+4)*2))
        cg.strokeEllipse(in: CGRect(x: circuitRect.minX - srcR, y: circuitRect.midY - srcR, width: srcR*2, height: srcR*2))
        drawText("U0", at: CGPoint(x: circuitRect.minX - srcR - 14, y: circuitRect.midY), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // Rv on top
        let rvX = circuitRect.minX + circuitRect.width * 0.4
        let rw: CGFloat = 46
        let rh: CGFloat = 18
        cg.clear(CGRect(x: rvX - rw/2 - 2, y: circuitRect.minY - rh/2 - 2, width: rw + 4, height: rh + 4))
        cg.stroke(CGRect(x: rvX - rw/2, y: circuitRect.minY - rh/2, width: rw, height: rh))
        drawText("Rv", at: CGPoint(x: rvX, y: circuitRect.minY - rh/2 - 12), color: strokeColor, font: .boldSystemFont(ofSize: 13))

        // LED on right branch
        let ledY = circuitRect.midY
        let dw: CGFloat = 26
        let dh: CGFloat = 26
        cg.clear(CGRect(x: circuitRect.maxX - dw - 6, y: ledY - dh/2 - 6, width: (dw+6)*2, height: dh + 12))

        cg.move(to: CGPoint(x: circuitRect.maxX - dw/2, y: ledY - dh/2))
        cg.addLine(to: CGPoint(x: circuitRect.maxX + dw/2, y: ledY - dh/2))
        cg.addLine(to: CGPoint(x: circuitRect.maxX, y: ledY + dh/2))
        cg.closePath()
        cg.strokePath()

        cg.move(to: CGPoint(x: circuitRect.maxX - dw/2, y: ledY + dh/2))
        cg.addLine(to: CGPoint(x: circuitRect.maxX + dw/2, y: ledY + dh/2))
        cg.strokePath()

        // Arrows
        for i in [0, 1] {
            let p1 = CGPoint(x: circuitRect.maxX + 14 + CGFloat(i)*10, y: ledY - 8)
            let p2 = CGPoint(x: circuitRect.maxX + 26 + CGFloat(i)*10, y: ledY - 20)
            cg.move(to: p1); cg.addLine(to: p2)
            cg.addLine(to: CGPoint(x: p2.x - 5, y: p2.y + 1))
        }
        cg.strokePath()

        drawText("LED", at: CGPoint(x: circuitRect.maxX + 32, y: ledY + 8), color: strokeColor, font: .boldSystemFont(ofSize: 12))
    }
}
