import CoreFoundation
import Foundation

enum Romanization {
    private static let pinyinSyllables: Set<String> = {
        Set(
            "a ai an ang ao ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cua cuan cui cun cuo da dai dan dang dao de dei deng di dia dian diao die ding diu dong dou du dua duan dui dun duo e ei en eng er fa fan fang fei fen feng fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun ka kai kan kang kao ke ken keng kong kou ku kua kuai kuan kuang kui kun kuo la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu long lou lu lua luan lue lun luo ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu na nai nan nang nao ne nei nen neng ni nia nian niang niao nie nin ning niu nong nou nu nua nuan nue nuo o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su sua suan sui sun suo ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tua tuan tui tun tuo wa wai wan wang wei wen weng wo wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo"
                .split(separator: " ").map(String.init)
        )
    }()

    static func aliases(for value: String) -> [String] {
        let source = value as CFString
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            source,
            CFRangeMake(0, CFStringGetLength(source)),
            CFOptionFlags(kCFStringTokenizerUnitWord),
            Locale(identifier: "zh_Hans") as CFLocale
        )

        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        var romanized = ""
        var initials = ""
        var hasRomanizedToken = false

        while type != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = CFStringCreateWithSubstring(kCFAllocatorDefault, source, range) as String? ?? ""
            let transcription =
                CFStringTokenizerCopyCurrentTokenAttribute(
                    tokenizer, kCFStringTokenizerAttributeLatinTranscription
                ) as? String
            let piece = ascii(transcription ?? token)
            guard !piece.isEmpty else {
                type = CFStringTokenizerAdvanceToNextToken(tokenizer)
                continue
            }

            romanized += piece
            if transcription != nil, token.unicodeScalars.contains(where: { !$0.isASCII }) {
                hasRomanizedToken = true
            }

            if containsHan(token) {
                let syllables = splitPinyin(piece, count: hanCount(in: token))
                initials += syllables.map { String($0.first!) }.joined()
            } else if token.unicodeScalars.allSatisfy({ $0.isASCII }) {
                initials += piece
            }

            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        guard hasRomanizedToken else { return [] }
        var result = [romanized]
        if initials != romanized { result.append(initials) }
        return result
    }

    private static func ascii(_ value: String) -> String {
        let folded = value.applyingTransform(.stripDiacritics, reverse: false) ?? value
        return folded.lowercased().unicodeScalars.filter { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 97 && scalar.value <= 122)
        }.map(String.init).joined()
    }

    private static func containsHan(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    private static func hanCount(in value: String) -> Int {
        value.unicodeScalars.filter { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }.count
    }

    private static func splitPinyin(_ value: String, count: Int) -> [String] {
        guard count > 0 else { return [] }
        var memo: [String: [String]?] = [:]

        func split(_ remainder: String, _ remaining: Int) -> [String]? {
            if remaining == 0 { return remainder.isEmpty ? [] : nil }
            let key = "\(remainder)|\(remaining)"
            if let cached = memo[key] { return cached }

            let candidates =
                pinyinSyllables
                .filter { remainder.hasPrefix($0) }
                .sorted { $0.count > $1.count }
            for syllable in candidates {
                let next = String(remainder.dropFirst(syllable.count))
                if let suffix = split(next, remaining - 1) {
                    let result = [syllable] + suffix
                    memo[key] = result
                    return result
                }
            }
            memo[key] = nil
            return nil
        }

        return split(value, count) ?? [value]
    }
}
