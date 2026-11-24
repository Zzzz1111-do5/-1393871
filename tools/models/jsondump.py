# carve.json 这类配置的紧凑写法：数字列表一行
import json


def dump(o, ind=0):
    sp = '  ' * ind
    if isinstance(o, dict):
        items = [sp + '  ' + json.dumps(k, ensure_ascii=False) + ': ' + dump(v, ind + 1).lstrip() for k, v in o.items()]
        return sp + '{\n' + ',\n'.join(items) + '\n' + sp + '}'
    if isinstance(o, list) and all(not isinstance(x, (dict, list)) for x in o):
        return sp + json.dumps(o, ensure_ascii=False)
    if isinstance(o, list) and all(isinstance(x, list) and all(not isinstance(y, (dict, list)) for y in x) for x in o):
        return sp + '[' + ', '.join(json.dumps(x) for x in o) + ']'
    if isinstance(o, list):
        return sp + '[\n' + ',\n'.join(dump(x, ind + 1) for x in o) + '\n' + sp + ']'
    return sp + json.dumps(o, ensure_ascii=False)
