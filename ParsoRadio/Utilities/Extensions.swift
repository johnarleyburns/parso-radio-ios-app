import Foundation
import UIKit

extension Double {
    var formattedTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let t = Int(self)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

extension UIImage {
    func squareScaled(to size: CGSize) -> UIImage {
        let minDim = min(self.size.width, self.size.height)
        let x = (self.size.width - minDim) / 2
        let y = (self.size.height - minDim) / 2
        let squareRect = CGRect(x: x, y: y, width: minDim, height: minDim)
        guard let cg = cgImage?.cropping(to: squareRect) else { return self }
        let square = UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            square.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension URLSession {
    static let app: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
}
