// AI を使わないときのフォルダ分け。「その他」ばかりにならないように、
// 1) 本文に今あるフォルダの名前が出てくればそこへ、
// 2) 今までしまったメモと言葉が近いフォルダへ（使うほど賢くなる）、
// 3) 話題ごとの言葉の辞書で一番多く当たった分類へ（今あるフォルダに似た名前があればそちらへ）入れる。
// 規則は Web 版と同じ。

import Foundation

extension Heuristics {
    static let topicsJa: [(String, [String])] = [
        ("料理・食", ["料理", "レシピ", "食べ", "食材", "調味", "野菜", "肉", "魚", "弁当", "醤油", "味噌", "炊", "焼く", "煮", "茹で", "ご飯", "パン", "卵", "冷凍", "冷蔵", "作り置き", "包丁", "フライパン", "レンジ", "おかず", "スープ", "カレー", "パスタ", "コーヒー", "お茶", "スイーツ", "お菓子", "外食", "ランチ", "カフェ", "居酒屋"]),
        ("健康・体", ["健康", "睡眠", "寝る", "寝つき", "運動", "筋トレ", "ストレッチ", "病院", "薬", "肩こり", "腰痛", "頭痛", "姿勢", "ダイエット", "体重", "風邪", "歯", "目の疲れ", "疲れ", "むくみ", "ヨガ", "ランニング", "散歩", "サプリ", "ビタミン", "花粉", "メンタル", "ストレス", "呼吸"]),
        ("美容・ファッション", ["肌", "スキンケア", "化粧", "メイク", "髪", "ヘア", "ネイル", "服", "コーデ", "ファッション", "靴", "香水", "日焼け", "美容"]),
        ("お金・節約", ["お金", "節約", "ポイント", "税", "ふるさと納税", "保険", "投資", "NISA", "iDeCo", "値下げ", "安く", "見積", "家計", "貯金", "クレカ", "クレジット", "割引", "クーポン", "セール", "銀行", "ローン", "年金", "給料", "副業", "確定申告", "支払", "料金", "円"]),
        ("PC・ガジェット", ["PC", "パソコン", "Mac", "Windows", "iPhone", "iPad", "Android", "スマホ", "ショートカット", "アプリ", "Excel", "Word", "スプレッドシート", "スクショ", "⌘", "Ctrl", "Chrome", "ブラウザ", "Wi-Fi", "WiFi", "充電", "バッテリー", "イヤホン", "キーボード", "ChatGPT", "Claude", "プログラ", "コード", "Git"]),
        ("仕事・勉強", ["仕事", "会議", "ミーティング", "メール", "資料", "プレゼン", "勉強", "英語", "面接", "上司", "部下", "会社", "職場", "転職", "就活", "履歴書", "報告", "企画", "締め切り", "締切", "タスク", "資格", "試験", "読書", "暗記", "学習", "単語"]),
        ("暮らし・家事", ["掃除", "洗濯", "シミ", "収納", "片付", "家事", "ゴミ", "引っ越", "部屋", "インテリア", "家具", "洗剤", "カビ", "トイレ", "風呂", "植物", "防災", "DIY", "修理", "電気代", "水道"]),
        ("家族・子育て", ["子ども", "子供", "赤ちゃん", "育児", "子育て", "保育園", "幼稚園", "学校", "宿題", "家族", "妊娠", "離乳食"]),
        ("ペット", ["ペット", "犬", "猫", "散歩させ", "トリミング", "動物病院"]),
        ("おでかけ・旅行", ["旅行", "旅", "ホテル", "新幹線", "飛行機", "観光", "荷造り", "空港", "電車", "駅", "ドライブ", "キャンプ", "温泉", "海外", "パスポート", "地図", "レジャー"]),
        ("買い物", ["買い物", "購入", "通販", "Amazon", "楽天", "おすすめ", "レビュー", "100均", "ダイソー", "無印", "ユニクロ", "コンビニ", "スーパー", "買う"]),
        ("趣味・エンタメ", ["映画", "ドラマ", "アニメ", "漫画", "マンガ", "小説", "音楽", "ゲーム", "カメラ", "写真", "推し", "ライブ", "Netflix", "YouTube"]),
        ("人づきあい", ["会話", "人間関係", "友達", "友人", "雑談", "話し方", "伝え方", "謝罪", "お礼", "敬語", "マナー", "プレゼント", "贈り物", "冠婚葬祭"]),
        ("手続き・書類", ["手続き", "書類", "役所", "申請", "免許", "マイナンバー", "住民票", "証明書", "契約", "更新", "解約"]),
        ("習慣・考え方", ["習慣", "考え方", "メモ術", "時間術", "朝活", "集中", "モチベーション", "目標", "やる気", "継続", "先延ばし"]),
    ]
    static let topicsEn: [(String, [String])] = [
        ("Food & Cooking", ["cook", "recipe", "food", "kitchen", "meal", "bake", "fry", "boil", "rice", "bread", "egg", "freez", "fridge", "lunch", "dinner", "breakfast", "coffee", "tea", "snack", "restaurant", "sauce", "vegetable"]),
        ("Health", ["sleep", "health", "exercise", "workout", "stretch", "posture", "doctor", "medicine", "headache", "back pain", "diet", "weight", "cold", "fever", "teeth", "tired", "yoga", "run", "walk", "vitamin", "stress", "breath"]),
        ("Beauty & Style", ["skin", "makeup", "hair", "nail", "outfit", "clothes", "fashion", "shoes", "perfume", "sunscreen"]),
        ("Money", ["money", "save", "saving", "budget", "tax", "price", "deal", "quote", "insurance", "invest", "bank", "loan", "credit", "coupon", "discount", "sale", "salary", "pay", "bill", "$"]),
        ("Tech", ["mac", "windows", "iphone", "ipad", "android", "phone", "shortcut", "app", "excel", "chrome", "browser", "wifi", "wi-fi", "battery", "charge", "keyboard", "laptop", "computer", "code", "git", "chatgpt", "claude"]),
        ("Work & Study", ["work", "meeting", "email", "slides", "present", "study", "interview", "boss", "office", "job", "resume", "report", "deadline", "task", "exam", "learn", "read", "book"]),
        ("Home", ["clean", "laundry", "stain", "storage", "move", "moving", "room", "furniture", "detergent", "mold", "toilet", "bath", "plant", "repair", "diy"]),
        ("Family & Kids", ["kid", "child", "baby", "parent", "school", "homework", "family", "daycare"]),
        ("Pets", ["pet", "dog", "cat", "vet", "puppy", "kitten"]),
        ("Travel", ["travel", "trip", "hotel", "flight", "pack", "airport", "train", "drive", "camp", "passport", "map", "vacation"]),
        ("Shopping", ["shop", "buy", "amazon", "review", "store", "groceries"]),
        ("Hobbies", ["movie", "film", "drama", "anime", "manga", "novel", "music", "game", "camera", "photo", "concert", "netflix", "youtube"]),
        ("People", ["conversation", "friend", "talk", "apolog", "thank", "manners", "gift", "wedding", "funeral"]),
        ("Paperwork", ["paperwork", "apply", "application", "license", "certificate", "contract", "renew", "cancel"]),
        ("Habits & Mindset", ["habit", "mindset", "focus", "motivation", "goal", "procrastinat", "routine", "productiv"]),
    ]

    /// 話題の辞書で当たった言葉（分類ごと）。英語は語の頭で当てる（"app" が "happy" に当たらないように）
    static func topicHits(_ text: String, language: AppLanguage) -> [(name: String, words: [String])] {
        let lower = text.lowercased()
        let topics = language == .ja ? topicsJa : topicsEn
        return topics.compactMap { name, words in
            let hit = words.filter { w in
                let k = w.lowercased()
                if language == .en, k.first?.isLetter == true {
                    return lower.range(of: "(^|[^a-z])" + NSRegularExpression.escapedPattern(for: k), options: .regularExpression) != nil
                }
                return lower.contains(k)
            }
            return hit.isEmpty ? nil : (name, hit)
        }
    }

    /// 言葉のかけら: 英数字の語（3 文字以上）、漢字・カタカナの続き（2〜6 文字ならそのまま）とその 2 文字ずつ。
    /// ひらがなは「する」「ます」などが多く、どのフォルダにも当たってしまうので使わない
    static func grams(_ s: String) -> Set<String> {
        var out = Set<String>()
        var ascii = "", run = ""
        func flushAscii() { if ascii.count >= 3 { out.insert(ascii) }; ascii = "" }
        func flushRun() {
            let c = Array(run)
            if c.count >= 2 {
                if c.count <= 6 { out.insert(run) }
                for i in 0..<(c.count - 1) { out.insert(String(c[i...i + 1])) }
            } else if c.count == 1 {
                out.insert(run)
            }
            run = ""
        }
        for ch in s.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                flushRun(); ascii.append(ch)
            } else if isKanjiOrKatakana(ch) {
                flushAscii(); run.append(ch)
            } else {
                flushAscii(); flushRun()
            }
        }
        flushAscii(); flushRun()
        return out
    }

    static func isKanjiOrKatakana(_ ch: Character) -> Bool {
        guard let u = ch.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(u) || (0x3400...0x4DBF).contains(u) || (0x30A0...0x30FF).contains(u) || u == 0x30FC
    }

    /// 今までのメモから、言葉が一番近いフォルダ（重みつきの点数）。めったに出ない言葉ほど重い
    static func profiles(_ notes: [Note]) -> [String: Set<String>] {
        let other = otherFolder
        var profile: [String: Set<String>] = [:]
        for n in notes where n.category != other && !n.category.isEmpty && !n.example {
            let words = [n.title, String(n.text.prefix(400)), n.summary] + n.tags + n.situations
            profile[n.category, default: grams(n.category)].formUnion(grams(words.joined(separator: " ")))
        }
        return profile
    }

    static func learnedFolder(_ text: String, profile: [String: Set<String>]) -> (name: String, score: Double)? {
        guard !profile.isEmpty else { return nil }
        let mine = grams(text)
        guard !mine.isEmpty else { return nil }
        var df: [String: Int] = [:]
        for g in mine { df[g] = profile.values.filter { $0.contains(g) }.count }
        let total = Double(profile.count)
        var best: (name: String, score: Double)?
        for (name, set) in profile {
            var s = 0.0
            for g in mine where set.contains(g) {
                // 1 文字の漢字は弱く、長いかけらは強く
                let len = g.count >= 3 ? 1.5 : (g.count == 1 ? 0.4 : 1)
                s += log(1 + total / Double(df[g] ?? 1)) * len
            }
            if s > (best?.score ?? 0) { best = (name, s) }
        }
        return best
    }

    /// フォルダとタグを推測する。notes は今までのメモ、folders は今あるフォルダ（空のフォルダも含む）
    public static func classify(_ text: String, notes: [Note] = [], folders: [String] = [], language: AppLanguage = .current) -> (folder: String, tags: [String]) {
        classify(text, notes: notes, folders: folders, language: language, profile: profiles(notes))
    }

    static func classify(_ text: String, notes: [Note], folders: [String], language: AppLanguage, profile: [String: Set<String>]) -> (folder: String, tags: [String]) {
        let other = otherFolder
        let lower = text.lowercased()
        let existing = Array(Set(folders + notes.map(\.category))).filter { !$0.isEmpty && $0 != other }.sorted()
        // 当たった言葉が多い順。同じ数なら辞書の順
        let hits = topicHits(text, language: language).enumerated()
            .sorted { $0.element.words.count != $1.element.words.count ? $0.element.words.count > $1.element.words.count : $0.offset < $1.offset }
            .map(\.element)
        let tags = Array((hits.first?.words ?? []).prefix(3))
        // 1) 本文にフォルダの名前（や「・」で区切った言葉）が出てくる
        let sep = CharacterSet(charactersIn: "・&/、, ")
        for name in existing.sorted(by: { $0.count > $1.count }) {
            let parts = [name] + name.components(separatedBy: sep).filter { $0.count >= 2 }
            if parts.contains(where: { $0.count >= 2 && lower.contains($0.lowercased()) }) { return (name, tags) }
        }
        let learned = learnedFolder(text, profile: profile)
        // 2) 今までのメモと言葉がよく重なる
        if let l = learned, l.score >= 3 { return (l.name, tags) }
        // 3) 話題の辞書。今あるフォルダに似た名前があればそちらへ（「お金」と「お金・節約」など）
        if let top = hits.first {
            if let near = existing.max(by: { nameSimilarity($0, top.name) < nameSimilarity($1, top.name) }), nameSimilarity(near, top.name) >= 0.5 {
                return (near, tags)
            }
            return (top.name, tags)
        }
        // 4) 少しでも近いフォルダ
        if let l = learned, l.score >= 1.5 { return (l.name, tags) }
        return (other, tags)
    }

    /// 「その他」「未分類」のような、何でも入る箱の名前か
    public static func isCatchAll(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return n.isEmpty || ["その他", "そのほか", "未分類", "雑多", "other", "others", "misc", "miscellaneous", "uncategorized", "general"].contains(n)
    }

    /// 「その他」のメモのうち、今なら別のフォルダに振り分けられるもの
    public static func resortSuggestions(_ notes: [Note], folders: [String] = [], language: AppLanguage = .current) -> [(id: String, folder: String)] {
        let other = otherFolder
        let filed = notes.filter { $0.category != other }
        let profile = profiles(filed)
        return notes.filter { $0.category == other && !$0.example }.compactMap { n in
            let r = classify([n.title, n.text, n.summary].joined(separator: "\n"), notes: filed, folders: folders, language: language, profile: profile)
            return r.folder == other ? nil : (n.id, r.folder)
        }
    }
}
