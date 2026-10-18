"""
Try the AI-scan prompt against DeepSeek from the command line, to iterate on
it without rebuilding the app. Mirrors AiScanService.buildPrompt in
lib/features/ai_scan/data/ai_scan_service.dart — keep the two in sync.

    python tools/try_prompt.py                      # built-in sample receipt
    python tools/try_prompt.py --text "瑞幸咖啡 -19.9 2026-10-12"
    python tools/try_prompt.py --image receipt.jpg  # needs: pip install paddleocr

Reads DEEPSEEK_API_KEY from the environment or the repo's .env file
(see .env.example). Don't commit real receipts or their output.
"""
import argparse
import datetime
import io
import json
import os
import sys
import urllib.request

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

EXPENSE = '餐饮、交通、购物、娱乐、账单、医疗、教育、居住、日用、通讯、服饰、数码、运动、宠物、居家、其他、订阅、学习'
INCOME = '工资、兼职、投资、礼金、退款、奖金、理财、副业、其他'

# Synthetic sample — not a real transaction.
SAMPLE = '示例便利店\n-23.50\n当前状态 支付成功\n支付时间 2026年10月12日 08:15:02\n商品 早餐套餐\n支付方式 零钱'


def load_env():
    path = os.path.join(os.path.dirname(__file__), '..', '.env')
    if not os.path.exists(path):
        return
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                key, _, val = line.partition('=')
                os.environ.setdefault(key.strip(), val.strip().strip('"\''))


def build_prompt(text):
    today = datetime.date.today().isoformat()
    return (f'从以下账单文字中提取记账信息，返回JSON：\n\n{text}\n\n'
            '格式：{"amount":正数,"type":"expense或income","category":"分类","date":"YYYY-MM-DD","note":"备注"}\n'
            '规则：\n'
            '- 付款、消费 → expense；收款、退款、工资 → income。amount 一律为正数。\n'
            f'- 支出分类只能从这些里选：{EXPENSE}\n'
            f'- 收入分类只能从这些里选：{INCOME}\n'
            '- 都不合适时填"其他"。\n'
            f'- 账单上没有日期时 date 填 null。今天是 {today}。\n'
            '- note 写商户名或商品，不超过 20 个字，不要包含订单号。')


def ocr(image_path):
    from paddleocr import PaddleOCR  # optional dependency
    result = PaddleOCR(lang='ch').ocr(image_path)
    return '\n'.join(line[1][0] for page in result if page for line in page)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--text', help='receipt text to parse')
    group.add_argument('--image', help='receipt image to OCR first')
    args = parser.parse_args()

    load_env()
    api_key = os.environ.get('DEEPSEEK_API_KEY')
    if not api_key:
        sys.exit('DEEPSEEK_API_KEY is not set (environment or .env)')

    text = ocr(args.image) if args.image else (args.text or SAMPLE)
    print('── input ──\n' + text + '\n')

    body = json.dumps({
        'model': 'deepseek-chat',
        'messages': [
            {'role': 'system', 'content': '你是精确的记账助手。只返回JSON，不返回其他内容。'},
            {'role': 'user', 'content': build_prompt(text)},
        ],
        'temperature': 0.1,
        'max_tokens': 256,
        'response_format': {'type': 'json_object'},
    }, ensure_ascii=False).encode('utf-8')
    req = urllib.request.Request(
        'https://api.deepseek.com/chat/completions', data=body,
        headers={'Content-Type': 'application/json; charset=utf-8',
                 'Authorization': f'Bearer {api_key}'})
    with urllib.request.urlopen(req, timeout=30) as resp:
        reply = json.loads(resp.read().decode('utf-8'))

    parsed = json.loads(reply['choices'][0]['message']['content'])
    usage = reply.get('usage', {}).get('total_tokens', '?')
    print(f'── {reply.get("model", "?")} ({usage} tokens) ──')
    print(json.dumps(parsed, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
