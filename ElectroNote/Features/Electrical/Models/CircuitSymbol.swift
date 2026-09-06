import Foundation
import UIKit
import SwiftUI

// MARK: - Categories

enum CircuitCategory: String, CaseIterable, Identifiable {
    case passives       = "Passive Bauteile"
    case sources        = "Quellen & Masse"
    case semiconductors = "Halbleiter & Op-Amps"
    case switches       = "Schalter & Kontakte"
    case measurement    = "Messtechnik & Lasten"
    case digital        = "Digital & Logik"
    case circuits       = "Fertige Stromkreise"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .passives:       return "rectangle"
        case .sources:        return "bolt.circle"
        case .semiconductors: return "triangle"
        case .switches:       return "switch.2"
        case .measurement:    return "gauge"
        case .digital:        return "square.split.2x2"
        case .circuits:       return "waveform.path.ecg"
        }
    }
}

// MARK: - Symbol Types

enum CircuitSymbolType: String, CaseIterable, Identifiable {
    // 1. Passive Bauelemente (DIN EN 60617 / IEC)
    case resistorDIN         = "resistor_din"
    case resistorUS          = "resistor_us"
    case potentiometer       = "potentiometer"
    case capacitor           = "capacitor"
    case capacitorPolarized  = "capacitor_polarized"
    case capacitorVariable   = "capacitor_variable"
    case inductor            = "inductor"
    case inductorIronCore    = "inductor_iron_core"
    case transformer         = "transformer"
    case fuse                = "fuse"
    case ptcResistor         = "ptc_resistor"
    case ntcResistor         = "ntc_resistor"
    case ldrResistor         = "ldr_resistor"

    // 2. Quellen & Energieversorgung
    case dcSource            = "dc_source"
    case batterySingle       = "battery_single"
    case batteryMulti        = "battery_multi"
    case acSource            = "ac_source"
    case currentSource       = "current_source"
    case groundGND           = "ground_gnd"
    case earthGroundPE       = "earth_ground_pe"
    case terminalPin         = "terminal_pin"

    // 3. Halbleiter & Dioden
    case diode               = "diode"
    case zenerDiode          = "zener_diode"
    case schottkyDiode       = "schottky_diode"
    case led                 = "led"
    case photodiode          = "photodiode"
    case npnTransistor       = "npn_transistor"
    case pnpTransistor       = "pnp_transistor"
    case nMosfet             = "n_mosfet"
    case pMosfet             = "p_mosfet"
    case opAmp               = "op_amp"

    // 4. Schalter & Relais
    case switchNormallyOpen  = "switch_no"
    case switchNormallyClose = "switch_nc"
    case switchToggleSPDT    = "switch_spdt"
    case relayContact        = "relay_contact"
    case junctionPoint       = "junction_point"
    case bridgeNoConnection  = "bridge_no_connection"

    // 5. Messtechnik & Lasten
    case voltmeter           = "voltmeter"
    case amperemeter         = "amperemeter"
    case ohmmeter            = "ohmmeter"
    case oscilloscope        = "oscilloscope"
    case lightBulb           = "light_bulb"
    case motor               = "motor"
    case generator           = "generator"

    // 6. Digitaltechnik & Logikgatter
    case logicAND            = "logic_and"
    case logicOR             = "logic_or"
    case logicNOT            = "logic_not"
    case logicNAND           = "logic_nand"
    case logicNOR            = "logic_nor"
    case logicXOR            = "logic_xor"

    // 7. Fertige Grundschaltungen (Templates)
    case circuitSimpleLamp   = "circuit_simple_lamp"
    case circuitSeriesR      = "circuit_series_r"
    case circuitParallelR    = "circuit_parallel_r"
    case circuitVoltageDiv   = "circuit_voltage_divider"
    case circuitWheatstone   = "circuit_wheatstone"
    case circuitRCTlowPass   = "circuit_rc_lowpass"
    case circuitRCHighPass   = "circuit_rc_highpass"
    case circuitGraetzBridge = "circuit_graetz_bridge"
    case circuitOpAmpInvert  = "circuit_opamp_inverting"
    case circuitOpAmpNonInv  = "circuit_opamp_non_inverting"
    case circuitLedDriver    = "circuit_led_driver"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .resistorDIN:         return "Widerstand (DIN EN 60617)"
        case .resistorUS:          return "Widerstand (US / Zickzack)"
        case .potentiometer:       return "Potentiometer / Poti"
        case .capacitor:           return "Kondensator"
        case .capacitorPolarized:  return "Elektrolyt-Kondensator (Elko)"
        case .capacitorVariable:   return "Drehkondensator"
        case .inductor:            return "Spule / Induktivität"
        case .inductorIronCore:    return "Drossel mit Eisenkern"
        case .transformer:         return "Transformator / Übertrager"
        case .fuse:                return "Schmelzsicherung"
        case .ptcResistor:         return "Kaltleiter (PTC)"
        case .ntcResistor:         return "Heißleiter (NTC)"
        case .ldrResistor:         return "Fotowiderstand (LDR)"

        case .dcSource:            return "Gleichspannungsquelle (DC)"
        case .batterySingle:       return "Batteriezelle (1 Zelle)"
        case .batteryMulti:        return "Batterie (Mehrzellig)"
        case .acSource:            return "Wechselspannungsquelle (AC)"
        case .currentSource:       return "Ideale Stromquelle"
        case .groundGND:           return "Masse (GND)"
        case .earthGroundPE:       return "Schutzerde (PE)"
        case .terminalPin:         return "Klemme / Anschlusspunkt"

        case .diode:               return "Diode (Standard PN)"
        case .zenerDiode:          return "Z-Diode (Zener)"
        case .schottkyDiode:       return "Schottky-Diode"
        case .led:                 return "Leuchtdiode (LED)"
        case .photodiode:          return "Fotodiode"
        case .npnTransistor:       return "NPN-Transistor (Bipolar)"
        case .pnpTransistor:       return "PNP-Transistor (Bipolar)"
        case .nMosfet:             return "N-Kanal MOSFET"
        case .pMosfet:             return "P-Kanal MOSFET"
        case .opAmp:               return "Operationsverstärker (Op-Amp)"

        case .switchNormallyOpen:  return "Schließer (Taster / Ein)"
        case .switchNormallyClose: return "Öffner (Taster / Aus)"
        case .switchToggleSPDT:    return "Wechselschalter (Umschalter)"
        case .relayContact:        return "Relais mit Kontakt"
        case .junctionPoint:       return "Knotenpunkt (Verbunden)"
        case .bridgeNoConnection:  return "Kreuzung (Nicht verbunden)"

        case .voltmeter:           return "Voltmeter (Spannung)"
        case .amperemeter:         return "Amperemeter (Strom)"
        case .ohmmeter:            return "Ohmmeter (Widerstand)"
        case .oscilloscope:        return "Oszilloskop / Signalanzeige"
        case .lightBulb:           return "Glühlampe / Meldeleuchte"
        case .motor:               return "Elektromotor (M)"
        case .generator:           return "Generator (G)"

        case .logicAND:            return "UND-Gatter (AND, &)"
        case .logicOR:             return "ODER-Gatter (OR, ≥1)"
        case .logicNOT:            return "NICHT-Inverter (NOT)"
        case .logicNAND:           return "NAND-Gatter"
        case .logicNOR:            return "NOR-Gatter"
        case .logicXOR:            return "XOR-Gatter (=1)"

        case .circuitSimpleLamp:   return "Einfacher Stromkreis (Lampe)"
        case .circuitSeriesR:      return "Reihenschaltung (R1 + R2)"
        case .circuitParallelR:    return "Parallelschaltung (R1 || R2)"
        case .circuitVoltageDiv:   return "Unbelasteter Spannungsteiler"
        case .circuitWheatstone:   return "Wheatstone-Messbrücke"
        case .circuitRCTlowPass:   return "RC-Tiefpassfilter"
        case .circuitRCHighPass:   return "RC-Hochpassfilter"
        case .circuitGraetzBridge: return "Grätz-Brückengleichrichter"
        case .circuitOpAmpInvert:  return "Invertierender OPV-Verstärker"
        case .circuitOpAmpNonInv:  return "Nicht-invertierender OPV"
        case .circuitLedDriver:    return "LED mit Vorwiderstand"
        }
    }

    var normKuerzel: String {
        switch self {
        case .resistorDIN, .resistorUS: return "R"
        case .potentiometer:            return "Poti"
        case .capacitor, .capacitorPolarized, .capacitorVariable: return "C"
        case .inductor, .inductorIronCore: return "L"
        case .transformer:              return "Tr"
        case .fuse:                     return "F"
        case .ptcResistor:              return "+t°"
        case .ntcResistor:              return "-t°"
        case .ldrResistor:              return "LDR"
        case .dcSource, .batterySingle, .batteryMulti: return "U / DC"
        case .acSource:                 return "U~ / AC"
        case .currentSource:            return "I"
        case .groundGND:                return "GND"
        case .earthGroundPE:            return "PE"
        case .terminalPin:              return "Pol"
        case .diode:                    return "D"
        case .zenerDiode:               return "ZD"
        case .schottkyDiode:            return "D_sch"
        case .led:                      return "LED"
        case .photodiode:               return "PD"
        case .npnTransistor, .pnpTransistor: return "Q / T"
        case .nMosfet, .pMosfet:        return "MOS"
        case .opAmp:                    return "OPV"
        case .switchNormallyOpen, .switchNormallyClose, .switchToggleSPDT: return "S"
        case .relayContact:             return "K / Rel"
        case .junctionPoint, .bridgeNoConnection: return "Knoten"
        case .voltmeter:                return "V"
        case .amperemeter:              return "A"
        case .ohmmeter:                 return "Ω"
        case .oscilloscope:             return "Oszill."
        case .lightBulb:                return "Lampe"
        case .motor:                    return "M"
        case .generator:                return "G"
        case .logicAND:                 return "&"
        case .logicOR:                  return "≥1"
        case .logicNOT:                 return "1 / Inv"
        case .logicNAND:                return "& / O"
        case .logicNOR:                 return "≥1 / O"
        case .logicXOR:                 return "=1"
        case .circuitSimpleLamp:        return "Kreis"
        case .circuitSeriesR:           return "Reihe"
        case .circuitParallelR:         return "Parallel"
        case .circuitVoltageDiv:        return "Teiler"
        case .circuitWheatstone:        return "Brücke"
        case .circuitRCTlowPass:        return "RC-TP"
        case .circuitRCHighPass:        return "RC-HP"
        case .circuitGraetzBridge:      return "Gleichr."
        case .circuitOpAmpInvert:       return "OPV Inv."
        case .circuitOpAmpNonInv:       return "OPV Non."
        case .circuitLedDriver:         return "LED-Vorw."
        }
    }

    var category: CircuitCategory {
        switch self {
        case .resistorDIN, .resistorUS, .potentiometer, .capacitor, .capacitorPolarized,
             .capacitorVariable, .inductor, .inductorIronCore, .transformer, .fuse,
             .ptcResistor, .ntcResistor, .ldrResistor:
            return .passives

        case .dcSource, .batterySingle, .batteryMulti, .acSource, .currentSource,
             .groundGND, .earthGroundPE, .terminalPin:
            return .sources

        case .diode, .zenerDiode, .schottkyDiode, .led, .photodiode, .npnTransistor,
             .pnpTransistor, .nMosfet, .pMosfet, .opAmp:
            return .semiconductors

        case .switchNormallyOpen, .switchNormallyClose, .switchToggleSPDT, .relayContact,
             .junctionPoint, .bridgeNoConnection:
            return .switches

        case .voltmeter, .amperemeter, .ohmmeter, .oscilloscope, .lightBulb, .motor, .generator:
            return .measurement

        case .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR, .logicXOR:
            return .digital

        case .circuitSimpleLamp, .circuitSeriesR, .circuitParallelR, .circuitVoltageDiv,
             .circuitWheatstone, .circuitRCTlowPass, .circuitRCHighPass, .circuitGraetzBridge,
             .circuitOpAmpInvert, .circuitOpAmpNonInv, .circuitLedDriver:
            return .circuits
        }
    }

    var keywords: [String] {
        switch self {
        case .resistorDIN, .resistorUS:
            return ["widerstand", "resistor", "ohm", "din", "r", "impedanz", "zickzack"]
        case .potentiometer:
            return ["potentiometer", "poti", "einstellwiderstand", "schleifer", "drehpoti"]
        case .capacitor, .capacitorPolarized, .capacitorVariable:
            return ["kondensator", "kapazitaet", "capacitor", "elko", "farad", "filter"]
        case .inductor, .inductorIronCore:
            return ["spule", "induktivitaet", "henry", "drossel", "choke", "eisenkern"]
        case .transformer:
            return ["transformator", "trafo", "uebertrager", "primaer", "sekundaer"]
        case .fuse:
            return ["sicherung", "schmelzsicherung", "fuse", "strom", "absicherung"]
        case .ptcResistor, .ntcResistor, .ldrResistor:
            return ["ptc", "ntc", "ldr", "sensor", "temperatur", "fotowiderstand", "thermo"]
        case .dcSource, .batterySingle, .batteryMulti:
            return ["batterie", "akku", "dc", "gleichspannung", "stromquelle", "plus", "minus"]
        case .acSource:
            return ["ac", "wechselspannung", "sinus", "frequenz", "netzspannung", "hertz"]
        case .currentSource:
            return ["stromquelle", "konstantstrom", "ampere", "ideal"]
        case .groundGND, .earthGroundPE, .terminalPin:
            return ["masse", "gnd", "erde", "pe", "schutzerde", "nullleiter", "klemme"]
        case .diode, .zenerDiode, .schottkyDiode:
            return ["diode", "zener", "schottky", "gleichrichter", "kathode", "anode"]
        case .led, .photodiode:
            return ["led", "leuchtdiode", "licht", "photodiode", "optokoppler"]
        case .npnTransistor, .pnpTransistor:
            return ["transistor", "npn", "pnp", "bipolar", "basis", "kollektor", "emitter"]
        case .nMosfet, .pMosfet:
            return ["mosfet", "fet", "gate", "drain", "source", "kanal"]
        case .opAmp:
            return ["opamp", "opv", "operationsverstaerker", "inverting", "komparator"]
        case .switchNormallyOpen, .switchNormallyClose, .switchToggleSPDT, .relayContact:
            return ["schalter", "taster", "wechselschalter", "relais", "kontakt"]
        case .junctionPoint, .bridgeNoConnection:
            return ["knoten", "verbindung", "loetpunkt", "kreuzung", "draht"]
        case .voltmeter, .amperemeter, .ohmmeter, .oscilloscope, .lightBulb, .motor, .generator:
            return ["messgeraet", "voltmeter", "amperemeter", "motor", "generator", "lampe"]
        case .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR, .logicXOR:
            return ["gatter", "logik", "and", "or", "not", "nand", "nor", "xor", "digital"]
        case .circuitSimpleLamp, .circuitSeriesR, .circuitParallelR, .circuitVoltageDiv,
             .circuitWheatstone, .circuitRCTlowPass, .circuitRCHighPass, .circuitGraetzBridge,
             .circuitOpAmpInvert, .circuitOpAmpNonInv, .circuitLedDriver:
            return ["stromkreis", "schaltung", "reihe", "parallel", "teiler", "bridge", "filter", "opv", "graetz"]
        }
    }
}
