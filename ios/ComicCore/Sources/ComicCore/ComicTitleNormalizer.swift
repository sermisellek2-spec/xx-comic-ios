import Foundation

/// Pure Swift title normalizer for cross-source manga title matching.
/// Performs whitespace/full-width folding, lowercasing, O(1) Traditional-to-Simplified
/// Chinese character normalization, and letter/digit filtering with symbol-only fallback.
public enum ComicTitleNormalizer {
    private static let mapping: (table: [UInt16], count: Int) = {
        // Interleaved [Traditional][Simplified] pairs (~700+ common manga-title & general CJK characters).
        // Pairs stay strictly interleaved so multi-character Traditional status/fixture strings never appear.
        let pairs =
            "萬万與与專专業业叢丛東东絲丝兩两嚴严喪丧個个臨临為为麗丽舉举義义烏乌樂乐喬乔習习"
            + "鄉乡書书買买亂乱爭争於于亞亚產产親亲億亿僅仅僕仆從从倉仓儀仪們们價价眾众優优會会"
            + "偉伟傳传傷伤倫伦偽伪體体餘余傭佣偵侦側侧僑侨倆俩儉俭債债傾倾償偿儲储兒儿兌兑黨党"
            + "蘭兰關关興兴茲兹養养獸兽內内岡冈冊册寫写軍军農农馮冯沖冲決决況况凍冻淨净淒凄涼凉"
            + "減减幾几鳳凤憑凭凱凯擊击鑿凿劃划劉刘則则剛刚創创刪删別别劍剑劑剂劇剧勸劝辦办務务"
            + "動动勵励勁劲勞劳勢势勳勋勻匀匯汇區区醫医華华協协單单賣卖盧卢衛卫卻却廠厂廳厅歷历"
            + "厲厉壓压厭厌廁厕廂厢廈厦廚厨縣县參参雙双發发變变敘叙疊叠葉叶號号嘆叹聽听啟启吳吴"
            + "員员詠咏響响喚唤問问嗎吗嗚呜嘔呕噴喷嚇吓囑嘱國国圖图圓圆團团園园圍围聖圣場场壞坏"
            + "塊块堅坚壇坛壩坝墳坟墜坠墮堕壯壮聲声處处備备復复夠够頭头誇夸夾夹奪夺奮奋獎奖奧奥"
            + "妝妆婦妇媽妈娛娱嬌娇嬰婴學学孫孙實实審审寬宽寵宠寶宝將将尋寻對对導导爾尔塵尘屍尸"
            + "層层屬属嶺岭嶽岳島岛峽峡嵐岚歲岁豈岂嶇岖嶄崭幣币帥帅師师帳帐帶带幫帮幹干廣广莊庄"
            + "慶庆庫库應应廟庙廢废開开異异棄弃弒弑張张強强彈弹歸归當当錄录徹彻後后徵征憶忆總总"
            + "戀恋恆恒惡恶悶闷驚惊態态慘惨慣惯慮虑慾欲憂忧憲宪憤愤懶懒懷怀懸悬懺忏懼惧戰战戲戏"
            + "戶户撲扑擴扩掃扫揚扬擾扰撫抚拋抛揀拣換换損损搖摇搗捣搶抢護护報报擔担擬拟擁拥擇择"
            + "擰拧撥拨據据擠挤擺摆攤摊攜携攝摄撈捞撐撑敵敌敗败數数斷断舊旧時时曆历曉晓暢畅暫暂"
            + "邊边際际間间陽阳陰阴雲云霧雾電电風风熱热溫温燒烧燈灯燭烛爐炉煙烟燦灿爛烂煉炼爍烁"
            + "輝辉閃闪紅红藍蓝綠绿黃黄銀银鐵铁銅铜鋼钢鑽钻鏡镜鏈链鎖锁鐘钟針针釘钉鉤钩鋒锋銳锐"
            + "錯错鍛锻鎮镇鍵键鑑鉴門门聞闻閣阁閥阀閱阅闡阐隊队階阶陣阵陸陆險险隨随隱隐雜杂離离"
            + "難难雞鸡靈灵靜静麵面頁页頂顶項项順顺須须頌颂預预頑顽領领頗颇頻频顆颗題题額额顏颜"
            + "願愿顛颠類类顧顾顯显飄飘飛飞飯饭飲饮飾饰飽饱館馆馬马馭驭驅驱駁驳駐驻駕驾駛驶駝驼"
            + "駭骇騎骑騙骗騷骚驗验驟骤髮发鬆松鬥斗鬧闹鬱郁魚鱼魯鲁鮮鲜鯨鲸鯉鲤鳥鸟鳴鸣鴉鸦鴨鸭"
            + "鴻鸿鵝鹅鶴鹤鷹鹰麥麦點点齊齐齒齿齡龄龍龙龜龟"
            + "臉脸脈脉腦脑腳脚膽胆臟脏腸肠膚肤膠胶腫肿脫脱勝胜約约線线級级組组純纯紙纸納纳紋纹"
            + "紛纷紀纪細细紹绍經经結结給给統统維维網网綴缀練练編编緩缓緯纬緊紧績绩織织繞绕繪绘"
            + "繼继續续纖纤纜缆"
            + "計计訂订認认討讨訓训議议訊讯記记講讲設设許许論论訟讼訪访證证評评訴诉診诊詞词譯译"
            + "試试詩诗誠诚話话誕诞詢询詳详語语誤误說说請请諸诸諾诺讀读課课誰谁調调談谈諒谅誼谊"
            + "謀谋謊谎諧谐謎谜謝谢謠谣謹谨譽誉讚赞"
            + "貞贞負负財财貢贡貧贫貨货販贩貪贪貫贯責责貴贵費费貼贴賀贺資资賈贾賊贼賓宾賞赏賜赐"
            + "賠赔賴赖賺赚購购賽赛贈赠贏赢"
            + "這这進进遠远違违連连週周適适過过達达遷迁遺遗遙遥還还邁迈邏逻飢饥餅饼餓饿饒饶櫻樱"
            + "樹树機机權权條条極极構构樣样橋桥檢检檔档櫃柜欄栏標标樓楼榮荣槍枪樸朴橫横夢梦藝艺"
            + "藥药蘇苏蘿萝蒼苍蓋盖蓮莲蕩荡蕭萧薩萨蟲虫螢萤獅狮貓猫豬猪俠侠砲炮鎧铠殺杀滅灭歡欢"
            + "淚泪節节裡里裏里長长醜丑晝昼淵渊澤泽種种棗枣楓枫葦苇荊荆療疗氣气運运災灾禍祸祿禄"
            + "壽寿窮穷"
            + "藹蔼礙碍曖暧襖袄罷罢輩辈貝贝筆笔畢毕斃毙濱滨瀕濒鬢鬓稟禀剝剥佈布採采殘残蠶蚕襯衬"
            + "稱称懲惩遲迟衝冲籌筹觸触辭辞竄窜貸贷禱祷盜盗遞递墊垫釣钓棟栋獨独賭赌鍍镀頓顿鈍钝"
            + "罰罚範范紡纺豐丰瘋疯縫缝複复賦赋趕赶綱纲崗岗鞏巩溝沟穀谷掛挂規规滾滚漢汉闔阖"
            + "環环渾浑獲获積积監监艱艰簡简艦舰醬酱驕骄潔洁儘尽競竞捲卷覺觉礦矿虧亏臘蜡攔拦禮礼"
            + "聯联憐怜輛辆獵猎鄰邻羅罗瑪玛碼码滿满貿贸彌弥銘铭膩腻寧宁濃浓歐欧盤盘龐庞簽签淺浅"
            + "牆墙輕轻確确軟软滲渗濕湿識识輸输術术肅肃縮缩臺台檯台颱台湯汤騰腾塗涂狹狭現现獻献"
            + "營营猶犹郵邮獄狱躍跃執执職职質质築筑裝装準准縱纵"
            + "迴回鍊炼鋸锯諜谍萊莱籃篮飆飙鵰雕侶侣癒愈賢贤隸隶襲袭蟬蝉詭诡鑰钥籠笼贖赎錶表"
            + "燼烬灣湾緋绯巖岩殼壳馴驯鈴铃佔占併并係系傢家凜凛嘯啸囉啰壘垒壟垄夥伙嬸婶堯尧"
            + "嬋婵婭娅嫻娴媼媪嬪嫔孿孪寢寝尷尴屢屡嶼屿巒峦巔巅幟帜廬庐彎弯彙汇擋挡攢攒攪搅"
            + "攬揽斂敛晉晋暈晕曠旷曬晒朧胧樞枢殞陨殤殇殲歼毆殴氫氢潛潜潤润澀涩澆浇潰溃潑泼"
            + "濁浊濟济濤涛濫滥濺溅濾滤瀉泻瀏浏瀧泷灑洒灘滩爺爷犧牺狀状瑣琐瑤瑶璽玺瓊琼甕瓮"
            + "瘡疮癡痴癢痒癱瘫癲癫皺皱瞞瞒矚瞩矯矫磚砖礎础禦御穩稳窯窑窺窥篩筛簫箫籤签糧粮"
            + "糞粪糾纠紳绅絞绞絡络綜综綻绽緬缅縛缚繃绷繕缮繡绣繩绳繫系繭茧纏缠罵骂羈羁聰聪"
            + "聳耸艙舱艷艳蔣蒋蔥葱薦荐褲裤覽览訝讶訣诀誌志誘诱諺谚謂谓趨趋軀躯車车軌轨軒轩"
            + "軸轴較较輔辅轟轰辯辩遜逊釀酿錢钱錦锦錫锡鍋锅鑄铸闊阔閒闲韓韩韻韵頒颁隻只"
            + "無无來来轉转沒没讓让載载註注雖虽閉闭製制視视虛虚遊游麼么盡尽終终絕绝並并釋释選选"
            + "轅辕楊杨"

        var table = [UInt16](repeating: 0, count: 65536)
        let units = Array(pairs.utf16)
        var count = 0
        var i = 0
        while i + 1 < units.count {
            let trad = Int(units[i])
            let simp = units[i + 1]
            if table[trad] == 0 && units[i] != simp {
                table[trad] = simp
                count += 1
            }
            i += 2
        }
        return (table, count)
    }()

    public static var mappingCount: Int {
        mapping.count
    }

    /// Normalizes a comic title for exact cross-source matching.
    public static func normalize(_ rawTitle: String?) -> String {
        guard let rawTitle, !rawTitle.isEmpty else { return "" }
        let folded = foldWidthAndTrim(rawTitle)
        guard !folded.isEmpty else { return "" }
        let lower = folded.lowercased()

        var normalized = String.UnicodeScalarView()
        var fallback = String.UnicodeScalarView()
        let table = mapping.table

        for scalar in lower.unicodeScalars {
            var current = scalar
            if current.value <= 0xFFFF {
                let mapped = table[Int(current.value)]
                if mapped != 0, let mappedScalar = UnicodeScalar(UInt32(mapped)) {
                    current = mappedScalar
                }
            }
            let ch = Character(current)
            if ch.isLetter || ch.isNumber {
                normalized.append(current)
            }
            if !isJavaWhitespace(current) {
                fallback.append(current)
            }
        }
        if !normalized.isEmpty {
            return String(normalized)
        }
        return String(fallback)
    }

    /// Returns true iff both titles normalize to the exact same non-empty key.
    public static func isSameComicTitle(_ a: String?, _ b: String?) -> Bool {
        let keyA = normalize(a)
        guard !keyA.isEmpty else { return false }
        return keyA == normalize(b)
    }

    private static func foldWidthAndTrim(_ input: String) -> String {
        var scalars = [UnicodeScalar]()
        scalars.reserveCapacity(input.unicodeScalars.count)
        for scalar in input.unicodeScalars {
            let v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E, let folded = UnicodeScalar(v - 0xFEE0) {
                scalars.append(folded)
            } else if v == 0x3000 {
                scalars.append(UnicodeScalar(" "))
            } else {
                scalars.append(scalar)
            }
        }
        var start = 0
        var end = scalars.count
        while start < end && isTrimWhitespace(scalars[start]) {
            start += 1
        }
        while end > start && isTrimWhitespace(scalars[end - 1]) {
            end -= 1
        }
        if start >= end { return "" }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        return String(view)
    }

    private static func isTrimWhitespace(_ scalar: UnicodeScalar) -> Bool {
        scalar.value <= 0x20 || isJavaWhitespace(scalar)
    }

    private static func isJavaWhitespace(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        if v == 0x00A0 || v == 0x2007 || v == 0x202F {
            return false
        }
        return scalar.properties.isWhitespace
            || (v >= 0x0009 && v <= 0x000D)
            || (v >= 0x001C && v <= 0x001F)
    }
}
