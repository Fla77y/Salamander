// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Native contracts for the actual Renamer parser/expander and helper bodies.
// Invoke-RenamerNativeTests.ps1 generates the included product definitions at
// build time. This is an isolated source-fragment harness, not a full SPL/SDK
// integration test. The capture fixture supplies already matched ASCII groups;
// it deliberately does not replace or claim to test the regular expression engine.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <array>
#include <clocale>
#include <cstdarg>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <regex>
#include <string>
#include <string_view>

#include "../../src/plugins/shared/lukas/str.h"
#include "../../src/plugins/renamer/renamer.rh2"

// The original tracing macros are observational only. The declarations below
// form the minimal isolated dependency boundary, not a copy of the algorithms.
#define CALL_STACK_MESSAGE_NONE
#define CALL_STACK_MESSAGE2(...)
#define CALL_STACK_MESSAGE3(...)

char LowerCase[256]{};
char UpperCase[256]{};
unsigned short CType[256]{};

struct CSourceFile;
#include "renamer_native_types.inc"
struct CaptureFixture
{
    int SubExpCount = 3;
    char* Startp[3]{};
    char* Endp[3]{};
};
struct GeneralFixture
{
    int StrNICmp(const char* left, const char* right, size_t n)
    {
        return _strnicmp(left, right, n);
    }
};
GeneralFixture general;
GeneralFixture* SG = &general;
class CRenamer
{
public:
    char ReplaceWith[MAX_PATH]{};
    CaptureFixture* RegExp = nullptr;
    int Error = 0, ErrorPos1 = -1, ErrorPos2 = -1;
    CRenamerErrorType ErrorType = retGenericError;
    BOOL ValidetaReplacePattern();
    BOOL SafeSubst(char* dest, int max, int& pos);
};
class CVarString
{
public:
    class CVariable
    {
    public:
        virtual ~CVariable() = default;
        virtual BOOL SetArguments(const char*, const char*, int&, const char*&, const char*&);
        virtual int Expand(char*&, char*, LPVOID) = 0;
    };
};

#include "renamer_native_product.inc"

namespace
{
constexpr char Guard = '@';
int total = 0, failed = 0, groupTotal = 0, groupFailed = 0;
const char* group = "";

void Begin(const char* name)
{
    group = name;
    groupTotal = groupFailed = 0;
}

void Check(bool ok, std::string_view label)
{
    ++total;
    ++groupTotal;
    if (ok) return;
    ++failed;
    ++groupFailed;
    // Keep a bounded log while still running/counting every independent row.
    if (groupFailed <= 20)
        std::cerr << "FAIL [" << group << "] " << label << '\n';
}

void End()
{
    std::cout << "Renamer native " << group << ": " << groupTotal - groupFailed
              << " PASS / " << groupFailed << " FAIL / " << groupTotal << " checks\n";
    if (groupFailed > 20)
        std::cout << "  " << groupFailed - 20 << " additional failure details suppressed\n";
}

std::string Describe(std::string_view text)
{
    std::string result = "\"";
    for (unsigned char c : text)
    {
        if (c == '\t') result += "\\t";
        else if (c == '\n') result += "\\n";
        else if (c == '\r') result += "\\r";
        else if (c == '\0') result += "\\0";
        else result += static_cast<char>(c);
    }
    return result + "\"";
}

void Numeric()
{
    Begin("numeric bounded grammar");
    const std::regex unsignedGrammar("[0-9]+");
    const std::regex signedGrammar("-?[0-9]+");
    const std::regex floatGrammar("-?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)");
    auto probe = [&](const std::string& text) {
        // The selected range does not end in NUL: consuming the following
        // sentinel must not change the lexical decision.
        std::string backing = "!" + text + "x123";
        const char* start = backing.data() + 1;
        const char* end = start + text.size();
        const std::string label = Describe(text);
        Check(!!IsValidInt(start,end,FALSE) == std::regex_match(text,unsignedGrammar), "unsigned " + label);
        Check(!!IsValidInt(start,end,TRUE) == std::regex_match(text,signedGrammar), "signed " + label);
        Check(!!IsValidFloat(start,end) == std::regex_match(text,floatGrammar), "float " + label);
    };
    const std::string alphabet = "019-.x+ ";
    // All lengths 0..4 over 8 symbols: 4681 distinct bounded strings.
    // Independent regex grammar, not a transcription of the implementation.
    auto enumerate = [&](auto&& self, std::string text, int remaining) -> void {
        probe(text);
        if (remaining == 0) return;
        for (char c : alphabet) self(self, text + c, remaining - 1);
    };
    enumerate(enumerate,"",4);
    for (const std::string& text : {std::string("1.5x"),std::string("1.2.3"),std::string("-.5"),
         std::string("1."),std::string("-."),
         std::string("12345.6789"),std::string("-00012.0040"),std::string("1e3"),
         std::string("0x10"),std::string("1,5"),std::string("\t1"),std::string("1\n"),
         std::string("1\r"),std::string("1\0",2),std::string("00000000000000000000")})
        probe(text);
    End();
}

// Test the real bounded readers against a PAGE_NOACCESS sentinel instead of
// relying on a NUL-terminated string. Keep SEH in a separate plain function
// (no objects requiring unwinding); an invalid read is a recorded failure.
__declspec(noinline) int ProbeGuardedRange(const char* first,const char* last,int kind)
{
    __try
    {
        if (kind==0) return !!IsValidInt(first,last,FALSE);
        if (kind==1) return !!IsValidInt(first,last,TRUE);
        return !!IsValidFloat(first,last);
    }
    __except (GetExceptionCode()==EXCEPTION_ACCESS_VIOLATION ?
              EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH)
    {
        return -2;
    }
}

void GuardedNumeric()
{
    Begin("numeric page-boundary safety");
    SYSTEM_INFO info{};
    GetSystemInfo(&info);
    const size_t page=info.dwPageSize;
    char* memory=static_cast<char*>(VirtualAlloc(nullptr,page*2,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE));
    if (!memory)
    {
        Check(false,"VirtualAlloc test prerequisite");
        End();
        return;
    }
    DWORD previous=0;
    if (!VirtualProtect(memory+page,page,PAGE_NOACCESS,&previous))
    {
        Check(false,"VirtualProtect test prerequisite");
        VirtualFree(memory,0,MEM_RELEASE);
        End();
        return;
    }
    struct Row { const char* text; int unsignedResult; int signedResult; int floatResult; };
    const Row cases[]={
        {"",0,0,0},{"1",1,1,1},{".",0,0,0},{"-",0,0,0},{"1.",0,0,1},
        {"-.5",0,0,1},{".x",0,0,0},{"-1",0,1,1},{"12",1,1,1}
    };
    const char* end=memory+page;
    for (const auto& item:cases)
    {
        const size_t length=std::strlen(item.text);
        char* start=memory+page-length;
        if (length) std::memcpy(start,item.text,length);
        const int expected[]={item.unsignedResult,item.signedResult,item.floatResult};
        for (int kind=0;kind<3;++kind)
        {
            int actual=ProbeGuardedRange(start,end,kind);
            Check(actual==expected[kind],"range "+Describe(item.text)+" parser="+
                std::to_string(kind)+" observed="+std::to_string(actual));
        }
    }
    if (!VirtualFree(memory,0,MEM_RELEASE)) Check(false,"VirtualFree test cleanup");
    End();
}

void Counter()
{
    Begin("counter arguments, formatting and bounded output");
    struct Good { const char* args; const char* zero; const char* one; const char* five; };
    const Good cases[] = {
        {"","0","1","5"}, {"1,2,d,3,0","001","003","011"},
        {"-2,1","-2","-1","3"}, {"9,-2","9","7","-1"},
        {"3,1.5","3","4","10"}, {"4,-.5","4","3","1"},
        {"4,1.","4","5","9"}, {"8,0","8","8","8"},
        {"15,1,x","f","10","14"}, {"15,1,X","F","10","14"},
        {"3,2,d,l,3,_","3__","5__","13_"}, {"7,1,4,0","0007","0008","0012"},
        {"9,1,d,2, "," 9","10","14"}, {"0,1,d,1,0","0","1","5"},
        {"2,0.25","2","2","3"}, {"-3,-0.5","-3","-3","-5"}
    };
    for (const auto& item : cases)
    {
        CVarCounter counter;
        int error = -1;
        const char *first = nullptr, *last = nullptr;
        const char* end = item.args + std::strlen(item.args);
        const bool accepted = !!counter.SetArguments(item.args,end,error,first,last);
        Check(accepted, std::string("accept ") + Describe(item.args));
        if (!accepted) continue;
        const int indices[] = {0,1,5};
        const char* answers[] = {item.zero,item.one,item.five};
        for (int i = 0; i < 3; ++i)
        {
            const std::string expected = answers[i];
            CExecuteNewNameParam param{};
            param.Counter = indices[i];
            // Supply a nonzero start offset and independent tail canaries.
            for (int capacity = 1; capacity <= static_cast<int>(expected.size()) + 2; ++capacity)
            {
                std::array<char,80> data;
                data.fill(Guard);
                char* start = data.data()+3;
                char* current = start;
                const int n = counter.Expand(current,start+capacity,&param);
                const bool inRange = current >= start && current <= start+capacity;
                const bool guards = std::all_of(data.begin(),data.begin()+3,[](char c){return c==Guard;}) &&
                    std::all_of(data.begin()+3+capacity,data.end(),[](char c){return c==Guard;});
                const bool exact = n == static_cast<int>(expected.size()) &&
                    current == start + expected.size() &&
                    std::string_view(start,expected.size()) == expected;
                // Expand alone may fill all available bytes; Execute reserves
                // the final NUL separately. Only demand success when it fits
                // including that NUL, and rejection when bytes cannot fit.
                bool contract = capacity > static_cast<int>(expected.size()) ? exact :
                    (capacity < static_cast<int>(expected.size()) ? n < 0 : (n < 0 || exact));
                Check(inRange && guards && contract, std::string("counter ")+Describe(item.args)+
                    " index="+std::to_string(indices[i])+" capacity="+std::to_string(capacity));
            }
        }
    }
    struct Bad { const char* args; int error; int first; int last; };
    const Bad invalid[] = {
        {"x,1",IDS_EXP_EXPECTSTART,0,1},
        {"1,1.5x",IDS_EXP_EXPECTSTEP,2,6},
        {"1,1.2.3",IDS_EXP_EXPECTSTEP,2,7},
        {"1,.",IDS_EXP_EXPECTSTEP,2,3},
        {"1,-.",IDS_EXP_EXPECTSTEP,2,4},
        {"1,+",IDS_EXP_EXPECTSTEP,2,3},
        {"1,1,q",IDS_EXP_EXPECTBASEALIGNWIDTH,4,5},
        {"1,1,d,-2",IDS_EXP_EXPECTALIGNWIDTH,6,8},
        {"1,1,d,l,-2",IDS_EXP_EXPECTWIDTH,8,10},
        {"1,1,d,3,ab",IDS_EXP_EXPECTFILL,8,10},
        {"1,1,d,3,0,extra",IDS_EXP_UNEXPECTEDARGUMENT,10,15}
    };
    for (const auto& item : invalid)
    {
        CVarCounter counter;
        int error = -1;
        const char *first = nullptr, *last = nullptr;
        const bool accepted = !!counter.SetArguments(item.args,item.args+std::strlen(item.args),error,first,last);
        Check(!accepted && error == item.error && first == item.args+item.first && last == item.args+item.last,
              std::string("reject and mark ")+Describe(item.args));
    }
    End();
}

void Replacement()
{
    Begin("regex replacement validation, captures and output limits");
    char matched[] = "aB-12";
    CaptureFixture captures;
    captures.Startp[0] = matched;   captures.Endp[0] = matched+5;
    captures.Startp[1] = matched;   captures.Endp[1] = matched+2;
    captures.Startp[2] = matched+3; captures.Endp[2] = matched+5;

    auto good = [&](const std::string& pattern, const std::string& expected) {
        CRenamer renamer;
        renamer.RegExp = &captures;
        std::memcpy(renamer.ReplaceWith,pattern.c_str(),pattern.size()+1);
        const bool accepted = !!renamer.ValidetaReplacePattern();
        Check(accepted,"accept "+Describe(pattern));
        if (!accepted) return; // SafeSubst requires successful validation.
        for (int capacity = 0; capacity <= static_cast<int>(expected.size())+2; ++capacity)
        {
            std::array<char,80> bytes;
            bytes.fill(Guard);
            int pos = 3;
            const int max = pos+capacity;
            const bool result = !!renamer.SafeSubst(bytes.data(),max,pos);
            const bool guards = std::all_of(bytes.begin(),bytes.begin()+3,[](char c){return c==Guard;}) &&
                std::all_of(bytes.begin()+max,bytes.end(),[](char c){return c==Guard;});
            const bool fits = capacity >= static_cast<int>(expected.size());
            const bool range = pos >= 3 && pos <= max;
            const bool exact = !fits || (pos == 3+static_cast<int>(expected.size()) &&
                std::string_view(bytes.data()+3,expected.size()) == expected);
            Check(result == fits && range && guards && exact,
                Describe(pattern)+" expected="+Describe(expected)+" capacity="+std::to_string(capacity));
        }
    };
    good("","");
    good("literal","literal");
    good("$$","$");
    good("$$$1","$aB");
    good("$0-$1-$2","aB-12-aB-12");
    good("$(1)","aB");
    good("${2}","12");
    good("$(01)","aB");
    good("$(1:)","aB");
    good("pre-$(1)-post","pre-aB-post");
    good("\\$2","\\12");

    // Every ASCII case spelling of each documented modifier, for both
    // bracket styles, using independent literal results.
    struct Modifier { const char* word; const char* expected; };
    const Modifier modifiers[] = {{"lower","ab"},{"upper","AB"},{"mixed","Ab"},{"stripdia","aB"}};
    for (const auto& modifier : modifiers)
    {
        const size_t len = std::strlen(modifier.word);
        for (unsigned mask=0; mask < (1u<<len); ++mask)
        {
            std::string spelling = modifier.word;
            for (size_t i=0;i<len;++i)
                if (mask & (1u<<i)) spelling[i] = static_cast<char>(spelling[i]-'a'+'A');
            good("$(1:"+spelling+")",modifier.expected);
            good("${1:"+spelling+"}",modifier.expected);
        }
    }
    struct Bad { const char* pattern; int error; int first; int last; };
    const Bad invalid[] = {
        {"$3",IDS_REP_BADREF,1,2}, {"$(9)",IDS_REP_BADREF,2,3},
        {"${2)",IDS_REP_EXPCLOSEPAR3,3,3}, {"$(1",IDS_REP_EXPCLOSEPAR3,3,3},
        {"$(1:bogus)",IDS_REP_EXPCLOSEPAR1,4,4}, {"$(1:upper}",IDS_REP_EXPCLOSEPAR2,9,9},
        {"$(x)",IDS_EXP_EXPECTSUBNUM1,2,2}, {"$x",IDS_EXP_EXPECTSUBNUM2,1,1},
        {"$",IDS_EXP_EXPECTSUBNUM2,1,1}
    };
    for (const auto& item : invalid)
    {
        CRenamer renamer;
        renamer.RegExp = &captures;
        std::strcpy(renamer.ReplaceWith,item.pattern);
        Check(!renamer.ValidetaReplacePattern() && renamer.ErrorType == retReplacePattern &&
              renamer.Error == item.error && renamer.ErrorPos1 == item.first && renamer.ErrorPos2 == item.last,
              std::string("reject and mark ")+Describe(item.pattern));
    }
    End();
}

void BoundedCopy()
{
    Begin("SafeCopy overloads and case mapping");
    const char source[] = "aBcDeFgHiJkLmNoP";
    const char upper[] = "ABCDEFGHIJKLMNOP";
    for (int offset=0;offset<=4;++offset)
        for (int limit=offset;limit<=16;++limit)
            for (int count=0;count<=16;++count)
                for (bool convert : {false,true})
                {
                    std::array<char,32> data;
                    data.fill(Guard);
                    int pos=offset;
                    const bool result = convert ? !!SafeCopy(data.data(),limit,pos,source,count,ccUpper)
                                                : !!SafeCopy(data.data(),limit,pos,source,count);
                    const bool fits = count <= limit-offset;
                    const int expectedPos = fits ? offset+count : offset;
                    std::array<char,32> expected;
                    expected.fill(Guard);
                    if (fits) std::memcpy(expected.data()+offset,convert?upper:source,count);
                    Check(result==fits && pos==expectedPos && data==expected,
                        std::string(convert?"upper":"raw")+" offset="+std::to_string(offset)+
                        " limit="+std::to_string(limit)+" count="+std::to_string(count));
                }
    End();
}

void PathsAndQuotes()
{
    Begin("bounded quote search, path fragments and shell quoting");
    struct Quote { const char* text; int length; char quote; char delimiter; int expected; };
    const Quote q[] = {
        {"",0,'\'',',',0},{"a,b",3,'\'',',',1},{"'a,b',c",7,'\'',',',5},
        {"'a,b",4,'\'',',',4},{"a,'b,c'",7,'\'',',',1},
        {"a,b",1,'\'',',',1},{"a,b",2,'\'',',',1},
        {"\"a,b\",c",7,'"',',',5},{"a;;b",4,'\'',';',1},
        {"''",2,'\'',',',2},{"','",3,'\'',',',3}
    };
    for (const auto& item:q)
        Check(StrQChr(item.text,item.text+item.length,item.quote,item.delimiter)==item.text+item.expected,
              "StrQChr "+Describe(item.text)+" range="+std::to_string(item.length));

    struct Root { const char* path; int length; const char* tail; };
    const Root roots[] = {
        {"C:\\folder\\a.txt",0,"C:\\folder\\a.txt"},{"C:\\folder\\a.txt",2,"folder\\a.txt"},
        {"C:\\folder\\a.txt",3,"folder\\a.txt"},{"C:\\folder\\a.txt",9,"a.txt"},
        {"C:\\folder\\a.txt",10,"a.txt"},{"\\\\host\\share\\a.txt",12,"a.txt"},
        {"\\\\host\\share\\a.txt",13,"a.txt"},{"C:\\",3,""}
    };
    for (const auto& item:roots)
    {
        std::string path=item.path;
        Check(std::string_view(StripRoot(path.data(),item.length))==item.tail,
              "StripRoot "+Describe(item.path)+" length="+std::to_string(item.length));
    }

    struct Dots { const char* path; CRenameSpec spec; const char* expected; };
    const Dots dots[] = {
        {"name...",rsFileName,"name"},{"file.ext",rsFileName,"file.ext"},
        {".hidden...",rsFileName,".hidden"},{"a..\\b...\\c.",rsRelativePath,"a\\b\\c"},
        {"a.b\\c.d",rsRelativePath,"a.b\\c.d"},
        {"C:\\a..\\b.",rsFullPath,"C:\\a\\b"},
        {"\\\\host\\share\\a.\\b...",rsFullPath,"\\\\host\\share\\a\\b"}
    };
    for (const auto& item:dots)
    {
        std::array<char,128> data;
        data.fill(Guard);
        const auto length=std::strlen(item.path);
        std::memcpy(data.data(),item.path,length+1);
        const int n=CutTrailingDots(data.data(),static_cast<int>(length),item.spec);
        Check(n==static_cast<int>(std::strlen(item.expected)) &&
            std::string_view(data.data(),static_cast<size_t>(std::max(n,0)))==item.expected &&
            n>=0 && data[static_cast<size_t>(n)]=='\0' &&
            std::all_of(data.begin()+length+1,data.end(),[](char c){return c==Guard;}),
            "CutTrailingDots "+Describe(item.path));
    }
    std::array<char,16> replaced{};
    std::strcpy(replaced.data(),"a,b,,c");
    Check(Replace(replaced.data(),',',';')==replaced.data() &&
          std::string_view(replaced.data())=="a;b;;c","Replace delimiter identity and all occurrences");

    auto escape = [](const std::string& input,bool fits,const std::string& expected) {
        std::array<char,4098> bytes;
        bytes.fill(Guard);
        const bool success=!!EscapeQuotes(input.c_str(),bytes.data()+1);
        const bool guards=bytes.front()==Guard && bytes.back()==Guard;
        Check(success==fits && guards &&
            (!fits || (std::memcmp(bytes.data()+1,expected.data(),expected.size())==0 &&
                       bytes[expected.size()+1]=='\0')),
            "EscapeQuotes input="+std::to_string(input.size())+" output="+std::to_string(expected.size()));
    };
    escape("",true,"");
    escape("abc",true,"abc");
    escape("a\"b",true,"a\\\"b");
    escape("\"\"",true,"\\\"\\\"");
    escape("a\\b",true,"a\\b");
    escape(std::string(4095,'a'),true,std::string(4095,'a'));
    escape(std::string(4096,'a'),false,"");
    escape(std::string(4093,'a')+"\"",true,std::string(4093,'a')+"\\\"");
    escape(std::string(4094,'a')+"\"",false,"");
    escape(std::string(2048,'"'),false,"");
    End();
}
}

int main()
{
    // Only ASCII contracts are certified by this isolated harness. Initialize
    // the same kind of Windows character tables used by the legacy plugin.
    std::setlocale(LC_ALL,"C");
    wchar_t chars[128]{};
    for (unsigned i=0;i<128;++i)
    {
        chars[i]=static_cast<wchar_t>(i);
        LowerCase[i]=static_cast<char>(reinterpret_cast<UINT_PTR>(CharLowerA(reinterpret_cast<LPSTR>(static_cast<UINT_PTR>(i)))));
        UpperCase[i]=static_cast<char>(reinterpret_cast<UINT_PTR>(CharUpperA(reinterpret_cast<LPSTR>(static_cast<UINT_PTR>(i)))));
    }
    if (!GetStringTypeW(CT_CTYPE1,chars,128,CType))
    {
        std::cerr << "FAIL: Windows ASCII character classification initialization\n";
        return 2;
    }
    Numeric();
    GuardedNumeric();
    Counter();
    Replacement();
    BoundedCopy();
    PathsAndQuotes();
    std::cout << "Renamer native summary: " << total-failed << " PASS / " << failed
              << " FAIL / " << total << " checks\n";
    return failed ? 1 : 0;
}
