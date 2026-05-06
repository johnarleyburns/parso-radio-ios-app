import Foundation
import os.log

enum Log {
    private static let subsystem = "guru.parso.ios-radio-app"
    static let general = Logger(subsystem: subsystem, category: "general")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let playback = Logger(subsystem: subsystem, category: "playback")
}
