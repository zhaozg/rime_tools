#!/usr/bin/env luajit

--[[
�ѹ���scel�ʿ���Ǳ�����ı���unicode���룬ÿ�����ֽ�һ���ַ������ĺ��ֻ���Ӣ����ĸ��
�ҳ���ÿ���ֵ�ƫ��λ�ü���
��Ҫ������
1.ȫ��ƴ����ò�������е�ƴ����ϣ��ֵ���
       ��ʽΪ(index,len,pinyin)���б�
       index: �����ֽڵ����� �������ƴ��������
       len: �����ֽڵ����� ƴ�����ֽڳ���
       pinyin: ��ǰ��ƴ����ÿ���ַ������ֽڣ��ܳ�len

2.��������
       ��ʽΪ(same,py_table_len,py_table,{word_len,word,ext_len,ext})��һ���б�
       same: �����ֽ� ���� ͬ��������
       py_table_len:  �����ֽ� ����
       py_table: �����б�ÿ�����������ֽ�,ÿ����������һ��ƴ��������

       word_len:�����ֽ� ���� �������Ĵ����ֽ�������
       word: ���Ĵ���,ÿ�����ĺ��������ֽڣ��ܳ���word_len
       ext_len: �����ֽ� ���� ������չ��Ϣ�ĳ��ȣ�������10
       ext: ��չ��Ϣ ǰ�����ֽ���һ������(��֪���ǲ��Ǵ�Ƶ) ��˸��ֽ�ȫ��0

      {word_len,word,ext_len,ext} һ���ظ�same�� ͬ���� ��ͬƴ����
--]]


-- ƴ����ƫ�ƣ�
local startPy = 0x1540

-- ��������ƫ��
local startChinese = 0x2628;

-- ȫ��ƴ����
local GPy_Table = {}

-- �������
-- Ԫ��(��Ƶ,ƴ��,���Ĵ���)���б�
local GTable = {}

local utf8 = require'utf8'
local function unichr(ord)
    if ord == nil then return nil end
    return utf8.char(ord)
end

-- ��ԭʼ�ֽ���תΪ�ַ���
local function byte2str(data)
    return data:gsub('..',function(w)
        w = unichr(string.unpack('H', w))
        if (w==' ') then return '' end
        if (w=='\r') then return '\n' end
        return w
    end)
end

-- ��ȡƴ����
local function getPyTable(data)
    if data:sub(1,4) ~= "\x9D\x01\x00\x00" then
        return nil
    end

    data = data:sub(5, -1)
    local off, idx, len, part = 1
    repeat
        idx, len, off = string.unpack('HH', data, off)
        part = data:sub(off, off+len-1)
        off = off + len
        GPy_Table[idx] = byte2str(part)
    until off > #data
end

-- ��ȡһ�������ƴ��
local function getWordPy(data)
    return data:gsub('..', function(w)
        w = string.unpack('H',w)
        return GPy_Table[w]
    end)
end

-- ��ȡһ������
local function getWord(data)
    return data:gsub('..', function(w)
        w = string.unpack('H',w)
        return GPy_Table[w]
    end)
end

-- ��ȡ���ı�
local function getChinese(data, off)

    local off = off or 1
    local same          --ͬ��������
    local py_table_len  --ƴ����������

    repeat
        same, py_table_len, off = string.unpack('HH', data, off)

        -- ƴ��������
        local py = getWordPy(data:sub(off, off + py_table_len - 1))
        off = off + py_table_len
        -- ���Ĵ���
        for i=1, same do
            -- ���Ĵ��鳤��
            local c_len
            c_len, off = string.unpack('H', data, off)

            -- ���Ĵ���
            local word
            word = byte2str(data:sub(off, off + c_len - 1))
            off = off + c_len

            --��չ���ݳ���
            local ext_len
            ext_len, off = string.unpack('H', data, off)

            --��Ƶ
            local count
            count = string.unpack('H', data, off)

            --����
            table.insert(GTable, {count, py, word})

            --���¸��ʵ�ƫ��λ��
            off = off + ext_len
        end
    until off > #data
end

local function deal(file_name)
    local fs = require'fs'
    local data = fs.readFileSync(file_name)

    if data:sub(1, 12) ~= "\x40\x15\x00\x00\x44\x43\x53\x01\x01\x00\x00\x00" then
        return nil, "ȷ����ѡ������ѹ�(.scel)�ʿ�?"
    end
--~     print("�ʿ����ƣ�", byte2str(data:sub(0x130+1,0x338)))
--~     print("�ʿ����ͣ�", byte2str(data:sub(0x338+1,0x540)))
--~     print("������Ϣ��", byte2str(data:sub(0x540+1,0xd40)))
--~     print("�ʿ�ʾ����", byte2str(data:sub(0xd40+1,startPy)))

    getPyTable(data:sub(startPy+1,startChinese))
    getChinese(data:sub(startChinese+1))
end

local function convert(tab)
  local dict = {}

  local max = 0
  local _, words, idx, simu, weight

  for i=1, #tab do
      v = tab[i]

      weight = v[1]  --��Ƶ
      simu = v[2]    --ƴ��
      words = v[3]   --�ʻ�

      weight = tonumber(weight)
      assert(weight)
      if max < weight then max = weight end


      table.insert(dict, {words, simu:gsub("'",' '), weight})
  end

  return dict,max
end

local function save_dict(dict,max)
  local f = io.open('luna_pinyin.almighty.dict.yaml','a+')
  for i=1, #dict do
    dict[i][3] = string.format('%2d%%', 100*dict[i][3]/max)
    f:write(table.concat(dict[i],'\t')..'\n')
  end
  f:close()
end


local function main()
    local fs = require'fs'

    --��Ҫת���Ĵʿ����������Ϳ�����
    local dir = 'scel'
    local files = fs.readdirSync(dir)
    for k, v in pairs(files) do
        deal(dir..'/'..v)
    end

    local dict,max = convert(GTable)
    save_dict(dict,max)
end

main()
