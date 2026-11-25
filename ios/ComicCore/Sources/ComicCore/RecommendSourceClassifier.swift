import Foundation

/// Classifies comic source FilterGroups into structured harvesting plans and normalizes
/// manga genre tags into a canonical Simplified-Chinese taxonomy.
public enum RecommendSourceClassifier {
    public static let canonicalGenres: [String] = [
        "热血", "恋爱", "悬疑", "奇幻", "冒险", "校园", "搞笑", "科幻",
        "都市", "古风", "推理", "治愈", "百合", "武侠", "格斗", "竞技",
        "魔幻", "玄幻", "穿越", "恐怖", "日常", "历史"
    ]

    private static let canonicalSet = Set(canonicalGenres)

    private static let tradToSimp: [UInt16] = {
        let pairs: [(UInt16, UInt16)] = [
            (0x71B1, 0x70ED), // 熱 -> 热
            (0x6200, 0x604B), // 戀 -> 恋
            (0x611B, 0x7231), // 愛 -> 爱
            (0x61F8, 0x60AC), // 懸 -> 悬
            (0x96AA, 0x9669), // 險 -> 险
            (0x5712, 0x56ED), // 園 -> 园
            (0x6B77, 0x5386), // 歷 -> 历
            (0x7652, 0x6108), // 癒 -> 愈
            (0x9B25, 0x6597), // 鬥 -> 斗
            (0x7AF6, 0x7ADE), // 競 -> 竞
            (0x9748, 0x7075), // 靈 -> 灵
            (0x7570, 0x5F02), // 異 -> 异
            (0x5075, 0x4FA6), // 偵 -> 侦
            (0x9A5A, 0x60CA), // 驚 -> 惊
            (0x842C, 0x4E07), // 萬 -> 万
            (0x85A6, 0x8350), // 薦 -> 荐
            (0x9580, 0x95E8), // 門 -> 门
            (0x6C23, 0x6C14), // 氣 -> 气
            (0x7DE8, 0x7F16), // 編 -> 编
            (0x8F2F, 0x8F91), // 輯 -> 辑
            (0x9078, 0x9009), // 選 -> 选
            (0x5F37, 0x5F3A), // 強 -> 强
            (0x8A55, 0x8BC4), // 評 -> 评
            (0x9EDE, 0x70B9), // 點 -> 点
            (0x64CA, 0x51FB), // 擊 -> 击
            (0x5EAB, 0x5E93), // 庫 -> 库
            (0x6642, 0x65F6), // 時 -> 时
            (0x9593, 0x95F4), // 間 -> 间
            (0x9023, 0x8FDE), // 連 -> 连
            (0x8F09, 0x8F7D), // 載 -> 载
            (0x7D50, 0x7ED3), // 結 -> 结
            (0x756B, 0x753B), // 畫 -> 画
            (0x985E, 0x7C7B), // 類 -> 类
            (0x984C, 0x9898), // 題 -> 题
            (0x6A19, 0x6807), // 標 -> 标
            (0x7C64, 0x7B7E), // 籤 -> 签
            (0x5287, 0x5267), // 劇 -> 剧
            (0x6B61, 0x6B22), // 歡 -> 欢
            (0x6A02, 0x4E50), // 樂 -> 乐
            (0x6A5F, 0x673A), // 機 -> 机
            (0x6230, 0x6218), // 戰 -> 战
            (0x98A8, 0x98CE), // 風 -> 风
            (0x4FE0, 0x4FA0), // 俠 -> 侠
            (0x7E3D, 0x603B), // 總 -> 总
            (0x8077, 0x804C), // 職 -> 职
            (0x5834, 0x573A), // 場 -> 场
            (0x5B78, 0x5B66), // 學 -> 学
            (0x570B, 0x56FD), // 國 -> 国
            (0x97D3, 0x97E9), // 韓 -> 韩
            (0x6B50, 0x6B27), // 歐 -> 欧
            (0x81FA, 0x53F0), // 臺 -> 台
            (0x9AD4, 0x4F53), // 體 -> 体
            (0x5EE3, 0x5E7F), // 廣 -> 广
            (0x7121, 0x65E0), // 無 -> 无
            (0x96DC, 0x6742), // 雜 -> 杂
            (0x8A8C, 0x5FD7), // 誌 -> 志
            (0x9918, 0x4F59), // 餘 -> 余
            (0x6771, 0x4E1C), // 東 -> 东
            (0x4E9E, 0x4E9A), // 亞 -> 亚
            (0x689D, 0x6761), // 條 -> 条
            (0x9577, 0x957F), // 長 -> 长
            (0x7DB2, 0x7F51), // 網 -> 网
            (0x904A, 0x6E38), // 遊 -> 游
            (0x8AAA, 0x8BF4), // 說 -> 说
            (0x8F15, 0x8F7B), // 輕 -> 轻
            (0x5BE6, 0x5B9E), // 實 -> 实
            (0x96D9, 0x53CC), // 雙 -> 双
            (0x5F8C, 0x540E), // 後 -> 后
            (0x5BAE, 0x5BAB), // 宮 -> 宫 (same)
            (0x60E1, 0x6076), // 惡 -> 恶
            (0x5FA9, 0x590D), // 復 -> 复
            (0x8F49, 0x8F6C), // 轉 -> 转
            (0x55AE, 0x5355), // 單 -> 单
            (0x8A9E, 0x8BED), // 語 -> 语
            (0x8A18, 0x8BB0), // 記 -> 记
            (0x9304, 0x5F55), // 錄 -> 录
            (0x6578, 0x6570), // 數 -> 数
            (0x512A, 0x4F18), // 優 -> 优
            (0x6607, 0x5347), // 昇 -> 升
            (0x9031, 0x5468), // 週 -> 周
            (0x66F8, 0x4E66), // 書 -> 书
            (0x6A94, 0x6863), // 檔 -> 档
            (0x6B0A, 0x6743), // 權 -> 权
            (0x8996, 0x89C6), // 視 -> 视
            (0x89BA, 0x89C9), // 覺 -> 觉
            (0x5BEB, 0x5199), // 寫 -> 写
            (0x507D, 0x4F2A), // 偽 -> 伪
            (0x7D14, 0x7EAF), // 純 -> 纯
            (0x6975, 0x6781), // 極 -> 极
            (0x7D55, 0x7EDD), // 絕 -> 绝
            (0x5C0D, 0x5BF9), // 對 -> 对
            (0x958B, 0x5F00), // 開 -> 开
            (0x95DC, 0x5173), // 關 -> 关
            (0x7D05, 0x7EA2), // 紅 -> 红
            (0x85CD, 0x84DD), // 藍 -> 蓝
            (0x50B3, 0x4F20), // 傳 -> 传
            (0x91AB, 0x533B), // 醫 -> 医
            (0x85E5, 0x836F), // 藥 -> 药
            (0x9F8D, 0x9F99), // 龍 -> 龙
            (0x9CF3, 0x51E4), // 鳳 -> 凤
            (0x528D, 0x5251), // 劍 -> 剑
            (0x7FA9, 0x4E49), // 義 -> 义
            (0x79AE, 0x793C), // 禮 -> 礼
            (0x8207, 0x4E0E), // 與 -> 与
            (0x5C08, 0x4E13), // 專 -> 专
            (0x5340, 0x533A), // 區 -> 区
            (0x5225, 0x522B), // 別 -> 别
            (0x820A, 0x65E7), // 舊 -> 旧
            (0x8F03, 0x8F83), // 較 -> 较
            (0x9032, 0x8FDB), // 進 -> 进
            (0x72C0, 0x72B6), // 狀 -> 状
            (0x614B, 0x6001), // 態 -> 态
            (0x9805, 0x9879), // 項 -> 项
            (0x9801, 0x9875), // 頁 -> 页
            (0x5716, 0x56FE), // 圖 -> 图
            (0x932F, 0x9519), // 錯 -> 错
            (0x8A66, 0x8BD5), // 試 -> 试
            (0x8ACB, 0x8BF7), // 請 -> 请
            (0x8A8D, 0x8BA4), // 認 -> 认
            (0x8B49, 0x8BC1), // 證 -> 证
            (0x865F, 0x53F7), // 號 -> 号
            (0x78BC, 0x7801), // 碼 -> 码
            (0x8CC7, 0x8D44), // 資 -> 资
            (0x8A0A, 0x8BAF), // 訊 -> 讯
            (0x7D61, 0x7EDC), // 絡 -> 络
            (0x7DDA, 0x7EBF), // 線 -> 线
            (0x96FB, 0x7535), // 電 -> 电
            (0x8166, 0x8111), // 腦 -> 脑
            (0x8CEA, 0x8D28), // 質 -> 质
            (0x8A71, 0x8BDD), // 話 -> 话
            (0x7BC0, 0x8282), // 節 -> 节
            (0x7D42, 0x7EC8), // 終 -> 终
            (0x9678, 0x9646), // 陸 -> 陆
            (0x5167, 0x5185), // 內 -> 内
            (0x7522, 0x4EA7), // 產 -> 产
            (0x7063, 0x6E7E), // 灣 -> 湾
            (0x83EF, 0x534E), // 華 -> 华
            (0x8ECD, 0x519B), // 軍 -> 军
            (0x85DD, 0x827A), // 藝 -> 艺
            (0x8853, 0x672F), // 術 -> 术
            (0x6232, 0x620F), // 戲 -> 戏
            (0x6BBA, 0x6740), // 殺 -> 杀
            (0x7375, 0x730E), // 獵 -> 猎
            (0x55AA, 0x4E27), // 喪 -> 丧
            (0x5C4D, 0x5C38), // 屍 -> 尸
            (0x7A2E, 0x79CD), // 種 -> 种
            (0x5BF5, 0x5BA0), // 寵 -> 宠
            (0x7D71, 0x7EDF), // 統 -> 统
            (0x7D1A, 0x7EA7), // 級 -> 级
            (0x596A, 0x593A), // 奪 -> 夺
            (0x8972, 0x88AD), // 襲 -> 袭
            (0x5E2B, 0x5E08), // 師 -> 师
            (0x8056, 0x5723), // 聖 -> 圣
            (0x5C07, 0x5C06), // 將 -> 将
            (0x76DC, 0x76D7), // 盜 -> 盗
            (0x8CCA, 0x8D3C), // 賊 -> 贼
            (0x6EC5, 0x706D), // 滅 -> 灭
            (0x9280, 0x94F6), // 銀 -> 银
            (0x8FF4, 0x56DE), // 迴 -> 回
            (0x84EE, 0x83B2), // 蓮 -> 莲
            (0x8ADC, 0x8C0D), // 諜 -> 谍
            (0x92F8, 0x952F), // 鋸 -> 锯
            (0x934A, 0x70BC), // 鍊 -> 炼
            (0x932B, 0x9521), // 錫 -> 锡
            (0x9190, 0x917F), // 釀 -> 酿
            (0x5076, 0x5076), // no-op
            (0x8F1D, 0x8F89), // 輝 -> 辉
            (0x7368, 0x72EC), // 獨 -> 独
            (0x6416, 0x6447), // 搖 -> 摇
            (0x6EFE, 0x6EDA), // 滾 -> 滚
            (0x9E97, 0x4E3D), // 麗 -> 丽
            (0x7D72, 0x4E1D), // 絲 -> 丝
            (0x9435, 0x94C1), // 鐵 -> 铁
            (0x98DB, 0x98DE), // 飛 -> 飞
            (0x76E3, 0x76D1), // 監 -> 监
            (0x7344, 0x72F1), // 獄 -> 狱
            (0x7C43, 0x7BEE), // 籃 -> 篮
            (0x52D5, 0x52A8), // 動 -> 动
            (0x80B2, 0x80B2), // 育 -> 育
            (0x904B, 0x8FD0), // 運 -> 运
            (0x6EAB, 0x6E29), // 溫 -> 温
            (0x7D33, 0x7EC5), // 紳 -> 绅
            (0x773E, 0x4F17), // 眾 -> 众
            (0x8CBB, 0x8D39), // 費 -> 费
            (0x8B80, 0x8BFB), // 讀 -> 读
            (0x95B1, 0x9605), // 閱 -> 阅
            (0x5718, 0x56E2), // 團 -> 团
            (0x7D04, 0x7EA6), // 約 -> 约
            (0x8A6D, 0x8BE1), // 詭 -> 诡
            (0x8B00, 0x8C0B), // 謀 -> 谋
            (0x969B, 0x9645), // 際 -> 际
            (0x8CFD, 0x8D5B), // 賽 -> 赛
            (0x4F86, 0x6765), // 來 -> 来
            (0x8266, 0x8230), // 艦 -> 舰
            (0x723A, 0x7237), // 爺 -> 爷
            (0x8AC7, 0x8C08), // 談 -> 谈
            (0x8ECA, 0x8F66), // 車 -> 车
            (0x71DF, 0x8425), // 營 -> 营
            (0x8C93, 0x732B), // 貓 -> 猫
            (0x6703, 0x4F1A), // 會 -> 会
            (0x8A0E, 0x8BA8), // 討 -> 讨
            (0x5C0E, 0x5BFC), // 導 -> 导
            (0x9A0E, 0x9A91), // 騎 -> 骑
            (0x5EE2, 0x5E9F), // 廢 -> 废
            (0x9670, 0x9634), // 陰 -> 阴
            (0x967D, 0x9633), // 陽 -> 阳
            (0x6F22, 0x6C49), // 漢 -> 汉
            (0x6B72, 0x5C81), // 歲 -> 岁
            (0x6B98, 0x6B8B)  // 殘 -> 残
        ]
        var table = [UInt16](repeating: 0, count: 65536)
        for (trad, simp) in pairs where trad != simp {
            table[Int(trad)] = simp
        }
        return table
    }()

    private static let genreSynonyms: [String: String] = {
        var map: [String: String] = [:]
        for canonical in canonicalGenres {
            map[canonical] = canonical
        }
        let entries: [(String, String)] = [
            // 恋爱
            ("爱情", "恋爱"), ("言情", "恋爱"), ("纯爱", "恋爱"), ("浪漫", "恋爱"),
            ("浪漫爱情", "恋爱"), ("青春恋爱", "恋爱"), ("后宫", "恋爱"), ("甜宠", "恋爱"),
            // 悬疑
            ("灵异", "悬疑"), ("鬼神", "悬疑"), ("神鬼", "悬疑"), ("悬疑灵异", "悬疑"),
            // 奇幻
            ("异世界", "奇幻"), ("异界", "奇幻"), ("架空", "奇幻"),
            // 校园
            ("青春", "校园"), ("校园生活", "校园"),
            // 搞笑
            ("欢乐", "搞笑"), ("欢乐向", "搞笑"), ("喜剧", "搞笑"), ("搞笑喜剧", "搞笑"),
            ("爆笑", "搞笑"), ("恶搞", "搞笑"), ("沙雕", "搞笑"), ("脑洞", "搞笑"),
            // 科幻
            ("机战", "科幻"), ("机甲", "科幻"), ("末世", "科幻"), ("末日", "科幻"), ("赛博朋克", "科幻"),
            // 都市
            ("职场", "都市"), ("霸总", "都市"), ("总裁", "都市"), ("霸道总裁", "都市"),
            ("豪门", "都市"), ("黑道", "都市"), ("现代", "都市"),
            // 古风
            ("宫廷", "古风"), ("古装", "古风"), ("古代", "古风"),
            // 推理
            ("侦探", "推理"), ("探案", "推理"),
            // 治愈
            ("萌系", "治愈"), ("温情", "治愈"), ("暖心", "治愈"),
            // 百合
            ("gl", "百合"), ("gl向", "百合"), ("轻百", "百合"),
            // 武侠
            ("侠客", "武侠"), ("江湖", "武侠"),
            // 格斗
            ("动作", "格斗"), ("搏击", "格斗"),
            // 竞技
            ("运动", "竞技"), ("体育", "竞技"), ("运动竞技", "竞技"),
            // 魔幻
            ("魔法", "魔幻"),
            // 玄幻
            ("异能", "玄幻"), ("修真", "玄幻"), ("修仙", "玄幻"), ("仙侠", "玄幻"),
            ("系统", "玄幻"), ("逆袭", "玄幻"),
            // 穿越
            ("重生", "穿越"), ("转生", "穿越"),
            // 恐怖
            ("惊悚", "恐怖"), ("猎奇", "恐怖"), ("生存", "恐怖"),
            // 日常
            ("生活", "日常"), ("生活日常", "日常"), ("美食", "日常"), ("美食家", "日常"),
            // 历史
            ("战争", "历史"), ("军事", "历史"),
            // 热血
            ("励志", "热血"), ("复仇", "热血")
        ]
        for (k, v) in entries {
            map[k] = v
        }
        return map
    }()

    private static let noisyExactTags: Set<String> = [
        "连载", "连载中", "完结", "已完结", "已完成", "完本", "休刊", "停更", "更新中",
        "漫画", "全部", "其他", "其它", "默认", "不限", "未知", "暂无", "无",
        "短篇", "长篇", "中篇", "条漫", "全彩", "彩漫", "黑白", "四格", "单行本",
        "画集", "图库", "轻小说", "同人", "原创", "未分类", "剧情",
        "国漫", "日漫", "韩漫", "美漫", "台漫", "港漫", "港台", "欧美", "大陆", "内地",
        "国产", "日本", "韩国", "台湾", "香港", "海外", "中国",
        "少年", "少女", "青年", "少男", "男频", "女频", "女青", "少年向", "少女向", "青年向",
        "少男漫画", "少女漫画", "青年漫画", "绅士漫画", "日本漫画", "韩国漫画", "大陆漫画",
        "普通", "免费", "付费", "vip", "热门", "最新", "推荐", "人气", "排行", "更新",
        "all", "default", "other", "none", "null", "unknown"
    ]

    private static let noisyContainsTokens: [String] = [
        "全部", "其他", "其它", "默认", "不限", "连载", "完结", "完本", "完成",
        "最新", "热门", "人气", "排行", "推荐", "更新", "免费", "付费", "收费",
        "地区", "状态", "进度", "排序", "受众", "字母", "版权", "未分类"
    ]

    private static let chapterNoiseRegex = try! NSRegularExpression(
        pattern: "^(?:第?\\d+.*|[0-9]+|.*(?:话|回|卷|章|季|集))$",
        options: []
    )

    private static let countSuffixRegex = try! NSRegularExpression(
        pattern: "\\s*[\\(（]\\d+[\\)）]\\s*$",
        options: []
    )

    private static let tagPrefixRegex = try! NSRegularExpression(
        pattern: "^(?:题材|类型|标签|分类|风格|少男|少女|青年|绅士)\\s*[·:：/-]\\s*",
        options: []
    )

    public static func toSimplifiedScalar(_ scalar: UnicodeScalar) -> UnicodeScalar {
        if scalar.value <= 0xFFFF {
            let mapped = tradToSimp[Int(scalar.value)]
            if mapped != 0, let out = UnicodeScalar(UInt32(mapped)) {
                return out
            }
        }
        return scalar
    }

    public static func toSimplifiedChar(_ ch: Character) -> Character {
        guard let first = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
            return ch
        }
        return Character(toSimplifiedScalar(first))
    }

    public static func toSimplified(_ input: String?) -> String {
        guard let input else { return "" }
        let trimmed = SearchRules.trim(input)
        guard !trimmed.isEmpty else { return "" }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(trimmed.unicodeScalars.count)
        for scalar in trimmed.unicodeScalars {
            var v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E {
                v -= 0xFEE0
            } else if v == 0x3000 {
                v = 0x20
            }
            if let s = UnicodeScalar(v) {
                out.append(toSimplifiedScalar(s))
            }
        }
        return SearchRules.trim(String(out))
    }

    public static func isNoisyTag(_ rawTag: String?) -> Bool {
        guard let rawTag else { return true }
        let clean = cleanTag(rawTag)
        guard !clean.isEmpty else { return true }
        let lower = clean.lowercased()
        if noisyExactTags.contains(lower) { return true }
        let range = NSRange(location: 0, length: lower.utf16.count)
        if chapterNoiseRegex.firstMatch(in: lower, options: [], range: range) != nil {
            return true
        }
        for noise in noisyContainsTokens where lower.contains(noise) {
            return true
        }
        return false
    }

    private static func cleanTag(_ raw: String?) -> String {
        guard let raw else { return "" }
        var s = toSimplified(raw)
        while s.hasPrefix("#") || s.hasPrefix("＃") {
            s.removeFirst()
        }
        let range1 = NSRange(location: 0, length: s.utf16.count)
        s = countSuffixRegex.stringByReplacingMatches(in: s, options: [], range: range1, withTemplate: "")
        let range2 = NSRange(location: 0, length: s.utf16.count)
        s = tagPrefixRegex.stringByReplacingMatches(in: s, options: [], range: range2, withTemplate: "")
        return SearchRules.trim(s)
    }

    public static func normalizeGenreTag(_ rawTag: String?) -> String {
        guard let rawTag else { return "" }
        let clean = cleanTag(rawTag)
        if clean.isEmpty || isNoisyTag(clean) { return "" }

        let lower = clean.lowercased()
        if let direct = genreSynonyms[lower] { return direct }

        if lower.hasSuffix("漫画") && lower.count > 2 {
            let stripped = SearchRules.trim(String(lower.dropLast(2)))
            if !isNoisyTag(stripped), let mapped = genreSynonyms[stripped] {
                return mapped
            }
        }
        if lower.hasSuffix("向") && lower.count > 2 {
            let stripped = SearchRules.trim(String(lower.dropLast(1)))
            if let mapped = genreSynonyms[stripped] {
                return mapped
            }
        }

        for canonical in canonicalGenres where lower.contains(canonical) {
            return canonical
        }
        for (key, value) in genreSynonyms where key.count >= 2 && lower.contains(key) {
            return value
        }
        return ""
    }

    public static func extractCanonicalGenres(_ rawTags: [String]?) -> [String] {
        guard let rawTags, !rawTags.isEmpty else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        for raw in rawTags {
            extractGenresInto(raw, out: &out, seen: &seen)
        }
        return out
    }

    public static func extractCanonicalGenres(text rawTagText: String?) -> [String] {
        guard let rawTagText, !SearchRules.trim(rawTagText).isEmpty else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        extractGenresInto(rawTagText, out: &out, seen: &seen)
        return out
    }

    private static func extractGenresInto(_ raw: String, out: inout [String], seen: inout Set<String>) {
        let simplified = toSimplified(raw)
        guard !simplified.isEmpty else { return }
        let separators = CharacterSet(charactersIn: "/,、·|｜;；").union(.whitespacesAndNewlines)
        let parts = simplified.components(separatedBy: separators)
        for part in parts {
            let clean = cleanTag(part)
            if clean.isEmpty || isNoisyTag(clean) { continue }
            let lower = clean.lowercased()
            if let exact = genreSynonyms[lower] {
                if seen.insert(exact).inserted {
                    out.append(exact)
                }
                continue
            }
            var matched: [(genre: String, offset: Int)] = []
            for canonical in canonicalGenres {
                if let range = lower.range(of: canonical) {
                    let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    matched.append((canonical, offset))
                }
            }
            if !matched.isEmpty {
                matched.sort { $0.offset < $1.offset }
                for item in matched where seen.insert(item.genre).inserted {
                    out.append(item.genre)
                }
            } else {
                let fallback = normalizeGenreTag(clean)
                if !fallback.isEmpty && seen.insert(fallback).inserted {
                    out.append(fallback)
                }
            }
        }
    }

    public static func buildCompleteFilterMap(
        groups: [SourceFilterGroup],
        targetGroupKey: String,
        targetValue: String
    ) -> [String: String] {
        var map: [String: String] = [:]
        if groups.isEmpty {
            if !targetGroupKey.isEmpty {
                map[targetGroupKey] = targetValue
            }
            return map
        }
        for group in groups where !group.key.isEmpty {
            if group.key == targetGroupKey {
                map[group.key] = targetValue
            } else {
                map[group.key] = defaultOptionValue(group)
            }
        }
        return map
    }

    private static func defaultOptionValue(_ group: SourceFilterGroup) -> String {
        guard !group.options.isEmpty else { return "all" }
        if let allOpt = group.options.first(where: { $0.value.lowercased() == "all" }) {
            return allOpt.value
        }
        for option in group.options {
            let label = toSimplified(option.label)
            if label == "全部" || label == "默认" || label == "不限" || label.hasPrefix("全部") {
                return option.value
            }
        }
        return group.options[0].value
    }

    private struct Candidate {
        let groupKey: String
        let option: SourceFilterOption
        let cleanLabel: String
        let score: Int
    }

    public static func detectFeaturedRecommendPlan(_ groups: [SourceFilterGroup]) -> FilterPlan? {
        guard !groups.isEmpty else { return nil }
        var best: Candidate?
        for group in groups where !group.key.isEmpty {
            for option in group.options {
                let label = cleanOptionLabel(option.label)
                if label.isEmpty || isNeutralOption(cleanLabel: label, value: option.value) { continue }
                let score = scoreFeaturedLabel(label)
                if score > 0 && (best == nil || score > best!.score) {
                    best = Candidate(groupKey: group.key, option: option, cleanLabel: label, score: score)
                }
            }
        }
        return best.map { toPlan(groups: groups, candidate: $0) }
    }

    private static func scoreFeaturedLabel(_ label: String) -> Int {
        if label.contains("不推荐") { return 0 }
        if label == "热门推荐" || label.contains("热门推荐") { return 100 }
        if label.contains("人气推荐") || label.contains("编辑推荐")
            || label.contains("精品推荐") || label.contains("推荐漫画")
            || label.contains("站长推荐") || label.contains("首页推荐") {
            return 85
        }
        if label.contains("强推") || label.contains("热推")
            || label.contains("精选") || label.contains("推荐") {
            return 70
        }
        return 0
    }

    public static func detectHotRankingPlan(_ groups: [SourceFilterGroup]) -> FilterPlan? {
        guard !groups.isEmpty else { return nil }
        let featured = detectFeaturedRecommendPlan(groups)
        var candidates: [Candidate] = []
        for group in groups where !group.key.isEmpty {
            for option in group.options {
                let label = cleanOptionLabel(option.label)
                if label.isEmpty || isNeutralOption(cleanLabel: label, value: option.value) { continue }
                let score = scoreHotCandidate(label: label, value: option.value)
                if score > 0 {
                    candidates.append(Candidate(groupKey: group.key, option: option, cleanLabel: label, score: score))
                }
            }
        }
        guard !candidates.isEmpty else { return nil }
        let indexed = candidates.enumerated().sorted { a, b in
            if a.element.score != b.element.score { return a.element.score > b.element.score }
            return a.offset < b.offset
        }.map(\.element)

        if let featured {
            for c in indexed where !isSameOption(c, plan: featured) {
                return toPlan(groups: groups, candidate: c)
            }
            return nil
        }
        return toPlan(groups: groups, candidate: indexed[0])
    }

    private static func scoreHotCandidate(label: String, value: String) -> Int {
        let valLower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if label.contains("升序") || label.contains("较早") || valLower.hasSuffix(":asc") {
            return 0
        }
        let isFeaturedStyle = label.contains("推荐") || label.contains("精选")
            || label.contains("强推") || label.contains("热推")

        var labelScore = 0
        if !isFeaturedStyle {
            if label.contains("热门排行") || label.contains("人气排行")
                || label.contains("漫画排行榜") || label.contains("热榜")
                || label.contains("热门榜") || label.contains("排行榜") {
                labelScore = 100
            } else if label.contains("热门优先") || label.contains("热门漫画")
                || label.contains("评分排行") || label.contains("收藏量")
                || label.contains("收藏排行") || label.contains("阅读量") {
                labelScore = 90
            } else if label == "热门" || label == "人气" || label == "排行"
                || label == "点击" || label.contains("热门")
                || label.contains("人气") || label.contains("排行")
                || label.contains("点击") || label.contains("热度") {
                labelScore = 75
            }
        }

        var valueScore = 0
        if valLower == "-popular" || valLower == "hots" || valLower == "hot" {
            valueScore = 65
        } else if valLower == "popular" {
            valueScore = 60
        } else if valLower == "hits" || valLower == "views:desc"
            || valLower == "favores:desc" || valLower == "field_follow"
            || valLower == "field_score" || valLower == "daily" {
            valueScore = 50
        }

        if isFeaturedStyle {
            return valueScore >= 60 ? 25 : 0
        }
        return max(labelScore, valueScore)
    }

    public static func detectLatestPlan(_ groups: [SourceFilterGroup]) -> FilterPlan? {
        guard !groups.isEmpty else { return nil }
        var best: Candidate?
        for group in groups where !group.key.isEmpty {
            for option in group.options {
                let label = cleanOptionLabel(option.label)
                if label.isEmpty || isNeutralOption(cleanLabel: label, value: option.value) { continue }
                let score = scoreLatestCandidate(group: group, label: label, value: option.value)
                if score > 0 && (best == nil || score > best!.score) {
                    best = Candidate(groupKey: group.key, option: option, cleanLabel: label, score: score)
                }
            }
        }
        return best.map { toPlan(groups: groups, candidate: $0) }
    }

    private static func scoreLatestCandidate(group: SourceFilterGroup, label: String, value: String) -> Int {
        let valLower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if label.contains("较早") || label.contains("升序") || valLower.hasSuffix(":asc") {
            return 0
        }
        if label.contains("最新上新") || label.contains("最新入库")
            || label.contains("最近更新") || label.contains("最新更新") {
            return 100
        }
        if label.contains("更新时间") {
            return 85
        }
        if label == "最新" || label == "更新" || label.contains("最新") || label.contains("更新") {
            return 75
        }
        let groupKey = group.key.lowercased()
        let groupLabel = toSimplified(group.label)
        let sortGroup = groupKey.contains("order") || groupKey.contains("sort")
            || groupLabel.contains("排序") || groupLabel.contains("分类")
        if sortGroup && (valLower == "latest" || valLower == "-datetime_updated"
            || valLower == "update" || valLower == "addtime"
            || valLower == "field_update" || valLower == "edittime:desc") {
            return 60
        }
        return 0
    }

    public static func detectGenrePlan(_ groups: [SourceFilterGroup], canonicalGenre: String?) -> FilterPlan? {
        guard !groups.isEmpty, let canonicalGenre else { return nil }
        var target = normalizeGenreTag(canonicalGenre)
        if target.isEmpty { target = toSimplified(canonicalGenre) }
        if target.isEmpty || isNoisyTag(target) { return nil }

        var best: Candidate?
        for group in groups where !group.key.isEmpty && isGenreEligibleGroup(group) {
            for option in group.options {
                let rawLabel = cleanOptionLabel(option.label)
                if rawLabel.isEmpty || isNeutralOption(cleanLabel: rawLabel, value: option.value) { continue }
                let score = scoreGenreOption(rawLabel: rawLabel, targetCanonical: target)
                if score > 0 && (best == nil || score > best!.score) {
                    best = Candidate(groupKey: group.key, option: option, cleanLabel: rawLabel, score: score)
                }
            }
        }
        return best.map { toPlan(groups: groups, candidate: $0) }
    }

    private static func isGenreEligibleGroup(_ group: SourceFilterGroup) -> Bool {
        let key = SearchRules.trim(group.key).lowercased()
        let label = toSimplified(group.label)

        let blockedKeys: Set<String> = [
            "state", "status", "finish", "isfinish", "is_end", "jindu",
            "order", "ordering", "sort", "sorttype", "letter", "day",
            "ischarge", "charge", "copyright", "audience", "cate", "level",
            "origin", "city", "zone"
        ]
        if blockedKeys.contains(key) { return false }

        if label.contains("状态") || label.contains("进度") || label.contains("排序")
            || label.contains("字母") || label.contains("地区") || label.contains("收费")
            || label.contains("受众") || label.contains("读者") || label.contains("星期")
            || label.contains("年份") || label.contains("版权") {
            return false
        }
        if key == "region" {
            return label.contains("题材") || label.contains("标签") || label.contains("分类")
                || label.contains("栏目") || label.contains("类型") || label.contains("主题")
                || label.isEmpty
        }
        return key.contains("theme") || key.contains("genre") || key.contains("tag")
            || key.contains("cid") || key.contains("category") || key.contains("type")
            || key.contains("subject")
            || label.contains("题材") || label.contains("标签") || label.contains("分类")
            || label.contains("类型") || label.contains("主题")
    }

    private static func scoreGenreOption(rawLabel: String, targetCanonical: String) -> Int {
        let cleaned = cleanTag(rawLabel)
        if cleaned.isEmpty || isNoisyTag(cleaned) { return 0 }
        if cleaned == targetCanonical { return 100 }

        let mapped = normalizeGenreTag(cleaned)
        if targetCanonical == mapped {
            let lower = cleaned.lowercased()
            if genreSynonyms[lower] != nil { return 90 }
            return 80
        }

        let extracted = extractCanonicalGenres(text: rawLabel)
        if extracted.contains(targetCanonical) {
            return extracted.count == 1 ? 85 : 75
        }
        return 0
    }

    private static func cleanOptionLabel(_ label: String) -> String {
        let s = toSimplified(label)
        let range = NSRange(location: 0, length: s.utf16.count)
        let stripped = countSuffixRegex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        return SearchRules.trim(stripped)
    }

    private static func isNeutralOption(cleanLabel: String, value: String) -> Bool {
        if value.lowercased() == "all" { return true }
        return cleanLabel == "全部" || cleanLabel == "默认"
            || cleanLabel == "不限" || cleanLabel.hasPrefix("全部")
    }

    private static func isSameOption(_ candidate: Candidate, plan: FilterPlan) -> Bool {
        candidate.groupKey == plan.targetGroupKey && candidate.option.value == plan.matchedValue
    }

    private static func toPlan(groups: [SourceFilterGroup], candidate: Candidate) -> FilterPlan {
        let map = buildCompleteFilterMap(
            groups: groups,
            targetGroupKey: candidate.groupKey,
            targetValue: candidate.option.value
        )
        return FilterPlan(
            filters: map,
            targetGroupKey: candidate.groupKey,
            matchedLabel: candidate.cleanLabel,
            matchedValue: candidate.option.value,
            priorityScore: candidate.score
        )
    }

    private static let maxInferDescriptionChars = 240
    private static let maxInferredGenres = 3

    private static let textGenreRules: [(keywords: [String], genres: [String])] = [
        (["异世界", "异界", "转生"], ["奇幻", "穿越"]),
        (["穿越", "重生", "穿书", "快穿", "胎穿"], ["穿越"]),
        (["勇者", "魔王", "地下城", "讨伐"], ["奇幻", "冒险"]),
        (["冒险", "公会", "迷宫", "寻宝", "远征"], ["冒险"]),
        (["奇幻", "精灵", "魔物", "史莱姆", "圣女", "龙族"], ["奇幻"]),
        (["魔幻", "魔法", "魔女", "巫师", "魔导", "咒语"], ["魔幻"]),
        (["修仙", "修真", "仙尊", "灵气", "炼气", "渡劫", "金丹", "元婴", "飞升", "灵脉", "玄幻", "异能", "丹药"], ["玄幻"]),
        (["宗门"], ["玄幻", "武侠"]),
        (["武侠", "武林", "侠客", "剑客", "门派", "内功"], ["武侠"]),
        (["仙侠"], ["古风", "玄幻"]),
        (["江湖"], ["古风", "武侠"]),
        (["古风", "宫廷", "王爷", "皇子", "长安", "皇宫", "后宫", "世子", "宫斗", "朝堂"], ["古风"]),
        (["历史", "三国", "战国", "幕府", "王朝", "大唐", "大明", "大宋", "大秦", "秦朝", "汉朝", "诸侯"], ["历史"]),
        (["校园", "学园", "学姐", "学妹", "青梅", "同桌", "高校", "社团", "转校生", "学生会"], ["校园"]),
        (["恋爱", "恋人", "告白", "婚约", "甜宠", "女友", "男友", "初恋", "暗恋", "言情", "纯爱", "相亲"], ["恋爱"]),
        (["百合", "轻百", "双女主"], ["百合"]),
        (["悬疑", "诡秘", "悬案", "疑案", "谜团"], ["悬疑"]),
        (["推理", "侦探", "密室", "谋杀", "刑警", "破案", "探案", "凶案", "法医"], ["悬疑", "推理"]),
        (["科幻", "机甲", "星际", "末世", "末日", "赛博", "未来", "星舰", "太空", "外星", "废土"], ["科幻"]),
        (["都市", "职场", "总裁", "霸总", "神豪", "医生", "律师", "打工", "社畜", "上班族", "豪门", "娱乐圈"], ["都市"]),
        (["搞笑", "沙雕", "爆笑", "吐槽", "喜剧", "恶搞", "欢乐", "无厘头"], ["搞笑"]),
        (["恐怖", "惊悚", "灵异", "鬼怪", "丧尸", "怪谈", "幽灵", "恶鬼", "僵尸", "厉鬼", "驱魔"], ["恐怖"]),
        (["格斗", "拳击", "武道", "剑豪", "格斗家", "拳皇", "空手道", "柔道"], ["热血", "格斗"]),
        (["热血", "死斗", "决斗"], ["热血"]),
        (["竞技", "篮球", "足球", "排球", "网球", "电竞", "赛车", "棒球", "羽毛球", "乒乓球", "甲子园"], ["竞技"]),
        (["治愈", "温馨", "猫咪", "露营", "慢生活"], ["治愈", "日常"]),
        (["日常", "美食", "料理", "咖啡馆", "便利店"], ["日常"])
    ]

    public static func inferGenresFromText(
        title: String?,
        subtitle: String?,
        description: String?
    ) -> [String] {
        var parts: [String] = []
        appendTrimmedPart(&parts, title, maxChars: -1)
        appendTrimmedPart(&parts, subtitle, maxChars: -1)
        appendTrimmedPart(&parts, description, maxChars: maxInferDescriptionChars)
        guard !parts.isEmpty else { return [] }
        let combined = parts.joined(separator: " ")
        let normalized = toSimplified(combined).lowercased()
        guard !normalized.isEmpty else { return [] }

        var matched = Set<String>()
        for rule in textGenreRules {
            for keyword in rule.keywords where normalized.contains(keyword) {
                for g in rule.genres {
                    matched.insert(g)
                }
                break
            }
        }
        guard !matched.isEmpty else { return [] }
        var ordered: [String] = []
        for canonical in canonicalGenres where matched.contains(canonical) {
            ordered.append(canonical)
            if ordered.count >= maxInferredGenres { break }
        }
        return ordered
    }

    private static func appendTrimmedPart(_ parts: inout [String], _ raw: String?, maxChars: Int) {
        guard let raw else { return }
        var trimmed = SearchRules.trim(raw)
        guard !trimmed.isEmpty else { return }
        if maxChars > 0 && trimmed.utf16.count > maxChars {
            trimmed = String(trimmed.prefix(maxChars))
        }
        parts.append(trimmed)
    }
}
