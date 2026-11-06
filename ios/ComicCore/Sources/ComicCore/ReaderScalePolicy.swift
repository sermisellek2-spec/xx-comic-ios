import Foundation

/// Display geometry only: never crops or allocates image pixels. Dimensions are display pixels.
public enum ReaderScalePolicy: Int, CaseIterable, Sendable {
    case smart = 0
    case fitScreen = 1
    case fitWidth = 2
    case fitHeight = 3
    case stretch = 4
    case original = 5

    public static let SMART: Int = 0
    public static let FIT_SCREEN: Int = 1
    public static let FIT_WIDTH: Int = 2
    public static let FIT_HEIGHT: Int = 3
    public static let STRETCH: Int = 4
    public static let ORIGINAL: Int = 5
    public static let COUNT: Int = 6

    public static func normalize(_ mode: Int) -> Int {
        mode >= 0 && mode < COUNT ? mode : SMART
    }

    public static func label(_ mode: Int) -> String {
        switch normalize(mode) {
        case FIT_SCREEN: return "适应屏幕"
        case FIT_WIDTH: return "适应宽度"
        case FIT_HEIGHT: return "适应高度"
        case STRETCH: return "拉伸"
        case ORIGINAL: return "原始尺寸"
        default: return "智能适应"
        }
    }

    public static func description(_ mode: Int) -> String {
        switch normalize(mode) {
        case FIT_SCREEN: return "等比显示整页，保留全部画面"
        case FIT_WIDTH: return "宽度铺满，超出高度可上下查看"
        case FIT_HEIGHT: return "高度铺满，超出宽度可左右拖动"
        case STRETCH: return "铺满阅读区域，画面比例会改变"
        case ORIGINAL: return "按解码像素显示，超大图仍受内存保护"
        default: return "普通页完整显示，长条图按宽从顶部阅读"
        }
    }

    public struct Geometry: Equatable, Sendable {
        public let scaleX: Float
        public let scaleY: Float
        public let left: Float
        public let top: Float
        public let width: Float
        public let height: Float

        public init(scaleX: Float, scaleY: Float, left: Float, top: Float, width: Float, height: Float) {
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.left = left
            self.top = top
            self.width = width
            self.height = height
        }
    }

    public static func geometry(enabled: Bool, mode: Int, scroll: Bool,
                                imageWidth: Int, imageHeight: Int,
                                viewportWidth: Int, viewportHeight: Int) -> Geometry {
        let iw = Float(max(1, imageWidth))
        let ih = Float(max(1, imageHeight))
        let vw = Float(max(1, viewportWidth))
        let vh = Float(max(1, viewportHeight))
        var selected = enabled ? normalize(mode) : (scroll ? FIT_WIDTH : FIT_SCREEN)
        if selected == SMART {
            selected = (ih / iw >= 2.2 && (vw * ih / iw) > (vh * 1.2)) ? FIT_WIDTH : FIT_SCREEN
        }
        var sx: Float
        var sy: Float
        switch selected {
        case FIT_WIDTH:
            sx = vw / iw
            sy = vw / iw
        case FIT_HEIGHT:
            sx = vh / ih
            sy = vh / ih
        case ORIGINAL:
            sx = 1.0
            sy = 1.0
        case STRETCH:
            sx = vw / iw
            sy = vh / ih
        default:
            let s = min(vw / iw, vh / ih)
            sx = s
            sy = s
        }
        let w = iw * sx
        let h = ih * sy
        let top = (scroll || h > vh) ? 0 : (vh - h) / 2.0
        let left = (vw - w) / 2.0
        return Geometry(scaleX: sx, scaleY: sy, left: left, top: top, width: w, height: h)
    }

    public static func scrollHeight(enabled: Bool, mode: Int, iw: Int, ih: Int, vw: Int, vh: Int) -> Int {
        max(1, Int(geometry(enabled: enabled, mode: mode, scroll: true,
                            imageWidth: iw, imageHeight: ih,
                            viewportWidth: vw, viewportHeight: vh).height.rounded()))
    }
}
