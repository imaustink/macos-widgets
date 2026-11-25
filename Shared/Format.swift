import Foundation

func fmtBytes(_ b: Double) -> String {
    let gi = b / pow(1024, 3)
    return gi >= 10 ? String(format: "%.0fG", gi) : String(format: "%.1fG", gi)
}

func fmtCores(_ m: Double) -> String {
    m >= 10_000 ? String(format: "%.0f", m / 1000) : String(format: "%.1f", m / 1000)
}

/// 320 -> "320m", 1500 -> "1.5"
func fmtMilli(_ m: Double) -> String {
    m < 1000 ? "\(Int(m.rounded()))m" : String(format: m < 10_000 ? "%.1f" : "%.0f", m / 1000)
}

/// Bytes -> "512M" / "1.4G"
func fmtMem(_ b: Double) -> String {
    let mi = b / pow(1024, 2)
    return mi < 1024 ? "\(Int(mi.rounded()))M" : fmtBytes(b)
}
