#!/usr/bin/env luajit

--[[
搜狗的scel词库就是保存的文本的unicode编码，每两个字节一个字符（中文汉字或者英文字母）
找出其每部分的偏移位置即可
主要两部分
1.全局拼音表，貌似是所有的拼音组合，字典序
       格式为(index,len,pinyin)的列表
       index: 两个字节的整数 代表这个拼音的索引
       len: 两个字节的整数 拼音的字节长度
       pinyin: 当前的拼音，每个字符两个字节，总长len

2.汉语词组表
       格式为(same,py_table_len,py_table,{word_len,word,ext_len,ext})的一个列表
       same: 两个字节 整数 同音词数量
       py_table_len:  两个字节 整数
       py_table: 整数列表，每个整数两个字节,每个整数代表一个拼音的索引

       word_len:两个字节 整数 代表中文词组字节数长度
       word: 中文词组,每个中文汉字两个字节，总长度word_len
       ext_len: 两个字节 整数 代表扩展信息的长度，好像都是10
       ext: 扩展信息 前两个字节是一个整数(不知道是不是词频) 后八个字节全是0

      {word_len,word,ext_len,ext} 一共重复same次 同音词 相同拼音表
--]]


-- 拼音表偏移，
local startPy = 0x1540

-- 汉语词组表偏移
local startChinese = 0x2628;

-- 全局拼音表
local GPy_Table = {}

-- 解析结果
-- 元组(词频,拼音,中文词组)的列表
local GTable = {}

local utf8 = require'utf8'
local function unichr(ord)
    if ord == nil then return nil end
    return utf8.char(ord)
end

-- 将原始字节码转为字符串
local function byte2str(data)
    return data:gsub('..',function(w)
        w = unichr(string.unpack('H', w))
        if (w==' ') then return '' end
        if (w=='\r') then return '\n' end
        return w
    end)
end

-- 获取拼音表
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

-- 获取一个词组的拼音
local function getWordPy(data)
    return data:gsub('..', function(w)
        w = string.unpack('H',w)
        return GPy_Table[w]
    end)
end

-- 获取一个词组
local function getWord(data)
    return data:gsub('..', function(w)
        w = string.unpack('H',w)
        return GPy_Table[w]
    end)
end

-- 读取中文表
local function getChinese(data, off)

    local off = off or 1
    local same          --同音词数量
    local py_table_len  --拼音索引表长度

    repeat
        same, py_table_len, off = string.unpack('HH', data, off)

        -- 拼音索引表
        local py = getWordPy(data:sub(off, off + py_table_len - 1))
        off = off + py_table_len
        -- 中文词组
        for i=1, same do
            -- 中文词组长度
            local c_len
            c_len, off = string.unpack('H', data, off)

            -- 中文词组
            local word
            word = byte2str(data:sub(off, off + c_len - 1))
            off = off + c_len

            --扩展数据长度
            local ext_len
            ext_len, off = string.unpack('H', data, off)

            --词频
            local count
            count = string.unpack('H', data, off)

            --保存
            table.insert(GTable, {count, py, word})

            --到下个词的偏移位置
            off = off + ext_len
        end
    until off > #data
end

local function deal(file_name)
    local fs = require'fs'
    local data = fs.readFileSync(file_name)

    if data:sub(1, 12) ~= "\x40\x15\x00\x00\x44\x43\x53\x01\x01\x00\x00\x00" then
        return nil, "确认你选择的是搜狗(.scel)词库?"
    end
--~     print("词库名称：", byte2str(data:sub(0x130+1,0x338)))
--~     print("词库类型：", byte2str(data:sub(0x338+1,0x540)))
--~     print("描述信息：", byte2str(data:sub(0x540+1,0xd40)))
--~     print("词库示例：", byte2str(data:sub(0xd40+1,startPy)))

    getPyTable(data:sub(startPy+1,startChinese))
    getChinese(data:sub(startChinese+1))
end

local function convert(tab)
  local dict = {}

  local max = 0
  local _, words, idx, simu, weight

  for i=1, #tab do
      v = tab[i]

      weight = v[1]  --词频
      simu = v[2]    --拼音
      words = v[3]   --词汇

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

    --将要转换的词库添加在这里就可以了
    local dir = 'scel'
    local files = fs.readdirSync(dir)
    for k, v in pairs(files) do
        deal(dir..'/'..v)
    end

    local dict,max = convert(GTable)
    save_dict(dict,max)
end

main()
