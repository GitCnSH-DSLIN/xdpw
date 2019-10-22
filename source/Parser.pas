// XD Pascal - a 32-bit compiler for Windows
// Copyright (c) 2009-2010, 2019, Vasiliy Tereshkov

{$I-}
{$H-}
{$J+}

unit Parser;


interface


uses Common, Scanner, CodeGen, Linker;


procedure CompileProgramOrUnit;



implementation


var
  IsUnit: Boolean;
  IsInterfaceSection: Boolean;



procedure CompileConstExpression(var ConstVal: TConst; var ConstValType: Integer); forward;
procedure CompileDesignator(var ValType: Integer; ForceCharToString: Boolean); forward;
procedure CompileExpression(var ValType: Integer; ForceCharToString: Boolean); forward;
procedure CompileStatement(LoopNesting: Integer); forward;
procedure CompileType(var DataType: Integer); forward;




procedure DeclareIdent(const Name: TString; Kind: TIdentKind; TotalNumParams: Integer; DataType: Integer; PassMethod: TPassMethod; ConstValue: LongInt; FracConstValue: Single; PredefProc: TPredefProc);
var
  i, AdditionalStackItems: Integer;
  Scope: TScope;
begin
if BlockStack[BlockStackTop].Index = 1 then Scope := GLOBAL else Scope := LOCAL;

i := GetIdentUnsafe(Name);

if (i > 0) and (Ident[i].Block = BlockStack[BlockStackTop].Index) then
  Error('Duplicate identifier ' + Name);

Inc(NumIdent);
if NumIdent > MAXIDENTS then
  Error('Maximum number of identifiers exceeded');
  
Ident[NumIdent].Name := Name;
Ident[NumIdent].Kind := Kind;
Ident[NumIdent].Scope := Scope;
Ident[NumIdent].RelocType := UNINITDATARELOC;
Ident[NumIdent].DataType := DataType;
Ident[NumIdent].UnitIndex := NumUnits;
Ident[NumIdent].Block := BlockStack[BlockStackTop].Index;
Ident[NumIdent].NestingLevel := BlockStackTop;
Ident[NumIdent].NumParams := 0;
Ident[NumIdent].PassMethod := PassMethod;
Ident[NumIdent].IsUnresolvedForward := FALSE;
Ident[NumIdent].IsStdCall := FALSE;
Ident[NumIdent].IsExported := IsInterfaceSection and (Scope = GLOBAL);
Ident[NumIdent].ForLoopNesting := 0;

case Kind of
  PROC, FUNC:
    if PredefProc = EMPTYPROC then
      begin
      Ident[NumIdent].Value := GetCodeSize;                              // Routine entry point address
      Ident[NumIdent].PredefProc := EMPTYPROC;
      end
    else
      begin
      Ident[NumIdent].Value := 0;
      Ident[NumIdent].PredefProc := PredefProc;                       // Predefined routine index
      end;

  VARIABLE:
    case Scope of
     GLOBAL:
       begin
       Ident[NumIdent].Value := UninitializedGlobalDataSize;                                 // Variable address (relocatable)
       UninitializedGlobalDataSize := UninitializedGlobalDataSize + TypeSize(DataType);
       end;// else

     LOCAL:
       if TotalNumParams > 0 then
         begin          
         if Ident[NumIdent].NestingLevel = 2 then                                            // Inside a non-nested routine
           AdditionalStackItems := 1                                                         // Return address
         else                                                                                // Inside a nested routine
           AdditionalStackItems := 2;                                                        // Return address, static link (hidden parameter)  

         with BlockStack[BlockStackTop] do
           begin
           Ident[NumIdent].Value := (AdditionalStackItems + TotalNumParams) * SizeOf(LongInt) - ParamDataSize;  // Parameter offset from EBP (>0)
           ParamDataSize := ParamDataSize + SizeOf(LongInt);                                   // Parameters always occupy 4 bytes each
           end
         end
       else
         with BlockStack[BlockStackTop] do
           begin
           Ident[NumIdent].Value := -LocalDataSize - TypeSize(DataType);                       // Local variable offset from EBP (<0)
           LocalDataSize := LocalDataSize + TypeSize(DataType);
           end;
    end; // case


  CONSTANT:
    if PassMethod = VALPASSING then                                     // Untyped constant
      if Types[DataType].Kind = REALTYPE then
        Ident[NumIdent].FracValue := FracConstValue                     // Real constant value
      else
        Ident[NumIdent].Value := ConstValue                             // Ordinal constant value
    else                                                                // Typed constant (actually an initialized global variable)    
      begin
      Ident[NumIdent].Kind := VARIABLE;
      Ident[NumIdent].Scope := GLOBAL;
      Ident[NumIdent].RelocType := INITDATARELOC;
      Ident[NumIdent].PassMethod := VALPASSING;
      
      Ident[NumIdent].Value := InitializedGlobalDataSize;               // Typed constant address (relocatable)
      InitializedGlobalDataSize := InitializedGlobalDataSize + TypeSize(DataType);      
      end;
      
  GOTOLABEL:
    Ident[NumIdent].IsUnresolvedForward := TRUE;

end;// case


if InitializedGlobalDataSize >= MAXINITIALIZEDDATASIZE then
  Error('Maximum initialized data size exceeded');

if UninitializedGlobalDataSize >= MAXUNINITIALIZEDDATASIZE then
  Error('Maximum uninitialized data size exceeded');

if BlockStack[BlockStackTop].LocalDataSize >= MAXSTACKSIZE then
  Error('Maximum local data size exceeded');

if BlockStack[BlockStackTop].ParamDataSize >= MAXSTACKSIZE then
  Error('Maximum parameter data size exceeded');

end; // DeclareIdent




procedure DeclarePredefinedIdents;
begin
// Constants
DeclareIdent('TRUE',  CONSTANT, 0, BOOLEANTYPEINDEX, VALPASSING, 1, 0.0, EMPTYPROC);
DeclareIdent('FALSE', CONSTANT, 0, BOOLEANTYPEINDEX, VALPASSING, 0, 0.0, EMPTYPROC);

// Types
DeclareIdent('INTEGER',  USERTYPE, 0, INTEGERTYPEINDEX,  VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('SMALLINT', USERTYPE, 0, SMALLINTTYPEINDEX, VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('SHORTINT', USERTYPE, 0, SHORTINTTYPEINDEX, VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('WORD',     USERTYPE, 0, WORDTYPEINDEX,     VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('BYTE',     USERTYPE, 0, BYTETYPEINDEX,     VALPASSING, 0, 0.0, EMPTYPROC);  
DeclareIdent('CHAR',     USERTYPE, 0, CHARTYPEINDEX,     VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('BOOLEAN',  USERTYPE, 0, BOOLEANTYPEINDEX,  VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('REAL',     USERTYPE, 0, REALTYPEINDEX,     VALPASSING, 0, 0.0, EMPTYPROC);
DeclareIdent('POINTER',  USERTYPE, 0, POINTERTYPEINDEX,  VALPASSING, 0, 0.0, EMPTYPROC);

// Procedures
DeclareIdent('INC',      PROC, 0, 0, VALPASSING, 0, 0.0, INCPROC);
DeclareIdent('DEC',      PROC, 0, 0, VALPASSING, 0, 0.0, DECPROC);
DeclareIdent('READ',     PROC, 0, 0, VALPASSING, 0, 0.0, READPROC);
DeclareIdent('WRITE',    PROC, 0, 0, VALPASSING, 0, 0.0, WRITEPROC);
DeclareIdent('READLN',   PROC, 0, 0, VALPASSING, 0, 0.0, READLNPROC);
DeclareIdent('WRITELN',  PROC, 0, 0, VALPASSING, 0, 0.0, WRITELNPROC);
DeclareIdent('NEW',      PROC, 0, 0, VALPASSING, 0, 0.0, NEWPROC);
DeclareIdent('DISPOSE',  PROC, 0, 0, VALPASSING, 0, 0.0, DISPOSEPROC);
DeclareIdent('BREAK',    PROC, 0, 0, VALPASSING, 0, 0.0, BREAKPROC);
DeclareIdent('CONTINUE', PROC, 0, 0, VALPASSING, 0, 0.0, CONTINUEPROC);  
DeclareIdent('EXIT',     PROC, 0, 0, VALPASSING, 0, 0.0, EXITPROC);
DeclareIdent('HALT',     PROC, 0, 0, VALPASSING, 0, 0.0, HALTPROC);

// Functions
DeclareIdent('SIZEOF', FUNC, 0, 0, VALPASSING, 0, 0.0, SIZEOFFUNC);
DeclareIdent('ORD',    FUNC, 0, 0, VALPASSING, 0, 0.0, ORDFUNC);
DeclareIdent('CHR',    FUNC, 0, 0, VALPASSING, 0, 0.0, CHRFUNC);
DeclareIdent('PRED',   FUNC, 0, 0, VALPASSING, 0, 0.0, PREDFUNC);
DeclareIdent('SUCC',   FUNC, 0, 0, VALPASSING, 0, 0.0, SUCCFUNC);
DeclareIdent('ROUND',  FUNC, 0, 0, VALPASSING, 0, 0.0, ROUNDFUNC);
DeclareIdent('TRUNC',  FUNC, 0, 0, VALPASSING, 0, 0.0, TRUNCFUNC);
DeclareIdent('ABS',    FUNC, 0, 0, VALPASSING, 0, 0.0, ABSFUNC);
DeclareIdent('SQR',    FUNC, 0, 0, VALPASSING, 0, 0.0, SQRFUNC);
DeclareIdent('SIN',    FUNC, 0, 0, VALPASSING, 0, 0.0, SINFUNC);
DeclareIdent('COS',    FUNC, 0, 0, VALPASSING, 0, 0.0, COSFUNC);
DeclareIdent('ARCTAN', FUNC, 0, 0, VALPASSING, 0, 0.0, ARCTANFUNC);
DeclareIdent('EXP',    FUNC, 0, 0, VALPASSING, 0, 0.0, EXPFUNC);
DeclareIdent('LN',     FUNC, 0, 0, VALPASSING, 0, 0.0, LNFUNC);
DeclareIdent('SQRT',   FUNC, 0, 0, VALPASSING, 0, 0.0, SQRTFUNC);
end;// DeclarePredefinedIdents




procedure DeclarePredefinedTypes;
begin
NumTypes := STRINGTYPEINDEX;

Types[ANYTYPEINDEX].Kind      := ANYTYPE;
Types[INTEGERTYPEINDEX].Kind  := INTEGERTYPE;
Types[SMALLINTTYPEINDEX].Kind := SMALLINTTYPE;
Types[SHORTINTTYPEINDEX].Kind := SHORTINTTYPE;
Types[WORDTYPEINDEX].Kind     := WORDTYPE;  
Types[BYTETYPEINDEX].Kind     := BYTETYPE;  
Types[CHARTYPEINDEX].Kind     := CHARTYPE;
Types[BOOLEANTYPEINDEX].Kind  := BOOLEANTYPE;
Types[REALTYPEINDEX].Kind     := REALTYPE;
Types[POINTERTYPEINDEX].Kind  := POINTERTYPE;
Types[FILETYPEINDEX].Kind     := FILETYPE;
Types[STRINGTYPEINDEX].Kind   := ARRAYTYPE;

Types[POINTERTYPEINDEX].BaseType := ANYTYPEINDEX;
Types[FILETYPEINDEX].BaseType    := ANYTYPEINDEX;

// Add new anonymous type: 1 .. MAXSTRLENGTH + 1
Inc(NumTypes);
if NumTypes > MAXTYPES then
  Error('Maximum number of types exceeded');

Types[NumTypes].Kind     := SUBRANGETYPE;
Types[NumTypes].BaseType := INTEGERTYPEINDEX;
Types[NumTypes].Low      := 1;
Types[NumTypes].High     := MAXSTRLENGTH + 1;
Types[NumTypes].Block    := BlockStack[BlockStackTop].Index;

Types[STRINGTYPEINDEX].BaseType    := CHARTYPEINDEX;
Types[STRINGTYPEINDEX].IndexType   := NumTypes;
Types[STRINGTYPEINDEX].IsOpenArray := FALSE;
end;// DeclarePredefinedTypes




function AllocateTempStorage(Size: Integer): Integer;
begin
with BlockStack[BlockStackTop] do
  begin
  TempDataSize := TempDataSize + Size;    
  Result := -LocalDataSize - TempDataSize;
  end;
end; // AllocateTempStorage




procedure CompileConstFactor(var ConstVal: TConst; var ConstValType: Integer);
var
  IdentIndex: Integer;
begin
case Tok.Kind of
  IDENTTOK:
    begin
    IdentIndex := GetIdent(Tok.Name);
    if Ident[IdentIndex].Kind <> CONSTANT then
      Error('Constant expected but ' + Ident[IdentIndex].Name + ' found')
    else
      begin
      ConstValType := Ident[IdentIndex].DataType;
      if Types[ConstValType].Kind = REALTYPE then
        ConstVal.FracValue := Ident[IdentIndex].FracValue
      else
        ConstVal.Value := Ident[IdentIndex].Value;
      NextTok;
      end;
    end;


  INTNUMBERTOK:
    begin
    ConstVal.Value := Tok.Value;
    ConstValType := INTEGERTYPEINDEX;
    NextTok;
    end;


  FRACNUMBERTOK:
    begin
    ConstVal.FracValue := Tok.FracValue;
    ConstValType := REALTYPEINDEX;
    NextTok;
    end;


  CHARLITERALTOK:
    begin
    ConstVal.Value := Tok.Value;
    ConstValType := CHARTYPEINDEX;
    NextTok;
    end;


  OPARTOK:       // Expression in parentheses expected
    begin
    NextTok;
    CompileConstExpression(ConstVal, ConstValType);
    EatTok(CPARTOK);
    end;


  NOTTOK:
    begin
    CompileConstFactor(ConstVal, ConstValType);
    ConstVal.Value := not ConstVal.Value;
    end 

else
  Error('Expression expected but ' + GetTokSpelling(Tok.Kind) + ' found');
end;// case

end;// CompileConstFactor




procedure CompileConstTerm(var ConstVal: TConst; var ConstValType: Integer);
var
  OpTok: TToken;
  RightConstVal: TConst;
  RightConstValType: Integer;

begin
CompileConstFactor(ConstVal, ConstValType);

while Tok.Kind in MultiplicativeOperators do
  begin
  OpTok := Tok;
  NextTok;
  CompileConstFactor(RightConstVal, RightConstValType);

  // Try to convert integer to real
  if ConversionToRealIsPossible(ConstValType, RightConstValType) then
    begin
    ConstVal.FracValue := ConstVal.Value;
    ConstValType := REALTYPEINDEX;
    end;
  if ConversionToRealIsPossible(RightConstValType, ConstValType) then
    begin
    RightConstVal.FracValue := RightConstVal.Value;
    RightConstValType := REALTYPEINDEX;
    end;

  // Special case: real division of two integers
  if (OpTok.Kind = DIVTOK) and ConversionToRealIsPossible(ConstValType, REALTYPEINDEX) and ConversionToRealIsPossible(RightConstValType, REALTYPEINDEX) then
    begin
    ConstVal.FracValue := ConstVal.Value;
    RightConstVal.FracValue := RightConstVal.Value;
    ConstValType := REALTYPEINDEX;
    RightConstValType := REALTYPEINDEX;
    end;

  ConstValType := GetCompatibleType(ConstValType, RightConstValType);
  CheckOperator(OpTok, ConstValType);

  if Types[ConstValType].Kind = REALTYPE then        // Real constants
    case OpTok.Kind of
      MULTOK:  ConstVal.FracValue := ConstVal.FracValue * RightConstVal.FracValue;
      DIVTOK:  if RightConstVal.FracValue <> 0 then
                 ConstVal.FracValue := ConstVal.FracValue / RightConstVal.FracValue
               else
                 Error('Constant division by zero')
    end
  else                                                    // Integer constants
    case OpTok.Kind of             
      MULTOK:  ConstVal.Value := ConstVal.Value  *  RightConstVal.Value;
      IDIVTOK: if RightConstVal.Value <> 0 then
                 ConstVal.Value := ConstVal.Value div RightConstVal.Value
               else
                 Error('Constant division by zero');  
      MODTOK:  if RightConstVal.Value <> 0 then
                 ConstVal.Value := ConstVal.Value mod RightConstVal.Value
               else
                 Error('Constant division by zero');
      SHLTOK:  ConstVal.Value := ConstVal.Value shl RightConstVal.Value;
      SHRTOK:  ConstVal.Value := ConstVal.Value shr RightConstVal.Value;
      ANDTOK:  ConstVal.Value := ConstVal.Value and RightConstVal.Value;
    end;

  end;// while

end;// CompileConstTerm



procedure CompileSimpleConstExpression(var ConstVal: TConst; var ConstValType: Integer);
var
  UnaryOpTok, OpTok: TToken;
  RightConstVal: TConst;
  RightConstValType: Integer;

begin
UnaryOpTok := Tok;
if UnaryOpTok.Kind in UnaryOperators then
  NextTok;

CompileConstTerm(ConstVal, ConstValType);

if UnaryOpTok.Kind in UnaryOperators then
  CheckOperator(UnaryOpTok, ConstValType);

if UnaryOpTok.Kind = MINUSTOK then      // Unary minus
  if Types[ConstValType].Kind = REALTYPE then
    ConstVal.FracValue := -ConstVal.FracValue
  else
    ConstVal.Value := -ConstVal.Value;

while Tok.Kind in AdditiveOperators do
  begin
  OpTok := Tok;
  NextTok;
  CompileConstTerm(RightConstVal, RightConstValType);

  // Try to convert integer to real
  if ConversionToRealIsPossible(ConstValType, RightConstValType) then
    begin
    ConstVal.FracValue := ConstVal.Value;
    ConstValType := REALTYPEINDEX;
    end;
  if ConversionToRealIsPossible(RightConstValType, ConstValType) then
    begin
    RightConstVal.FracValue := RightConstVal.Value;
    RightConstValType := REALTYPEINDEX;
    end;  

  ConstValType := GetCompatibleType(ConstValType, RightConstValType);
  CheckOperator(OpTok, ConstValType);

  if Types[ConstValType].Kind = REALTYPE then       // Real constants
    case OpTok.Kind of
      PLUSTOK:  ConstVal.FracValue := ConstVal.FracValue  +  RightConstVal.FracValue;
      MINUSTOK: ConstVal.FracValue := ConstVal.FracValue  -  RightConstVal.FracValue;
    end
  else                                                  // Integer constants
    case OpTok.Kind of
      PLUSTOK:  ConstVal.Value := ConstVal.Value  +  RightConstVal.Value;
      MINUSTOK: ConstVal.Value := ConstVal.Value  -  RightConstVal.Value;
      ORTOK:    ConstVal.Value := ConstVal.Value  or RightConstVal.Value;
      XORTOK:   ConstVal.Value := ConstVal.Value xor RightConstVal.Value;
    end;

  end;// while

end;// CompileSimpleConstExpression



procedure CompileConstExpression{(var ConstVal: TConst; var ConstValType: Integer)};
var
  OpTok: TToken;
  RightConstVal: TConst;
  RightConstValType: Integer;
  Yes: Boolean;

begin
Yes := FALSE;
CompileSimpleConstExpression(ConstVal, ConstValType);

if Tok.Kind in RelationOperators then
  begin
  OpTok := Tok;
  NextTok;
  CompileSimpleConstExpression(RightConstVal, RightConstValType);

  // Try to convert integer to real
  if ConversionToRealIsPossible(ConstValType, RightConstValType) then
    begin
    ConstVal.FracValue := ConstVal.Value;
    ConstValType := REALTYPEINDEX;
    end;
  if ConversionToRealIsPossible(RightConstValType, ConstValType) then
    begin
    RightConstVal.FracValue := RightConstVal.Value;
    RightConstValType := REALTYPEINDEX;
    end;

  GetCompatibleType(ConstValType, RightConstValType);
  CheckOperator(OpTok, ConstValType);

  if Types[ConstValType].Kind = REALTYPE then
    case OpTok.Kind of
      EQTOK: Yes := ConstVal.FracValue =  RightConstVal.FracValue;
      NETOK: Yes := ConstVal.FracValue <> RightConstVal.FracValue;
      LTTOK: Yes := ConstVal.FracValue <  RightConstVal.FracValue;
      LETOK: Yes := ConstVal.FracValue <= RightConstVal.FracValue;
      GTTOK: Yes := ConstVal.FracValue >  RightConstVal.FracValue;
      GETOK: Yes := ConstVal.FracValue >= RightConstVal.FracValue;
    end
  else
    case OpTok.Kind of
      EQTOK: Yes := ConstVal.Value =  RightConstVal.Value;
      NETOK: Yes := ConstVal.Value <> RightConstVal.Value;
      LTTOK: Yes := ConstVal.Value <  RightConstVal.Value;
      LETOK: Yes := ConstVal.Value <= RightConstVal.Value;
      GTTOK: Yes := ConstVal.Value >  RightConstVal.Value;
      GETOK: Yes := ConstVal.Value >= RightConstVal.Value;
    end;

  if Yes then ConstVal.Value := 1 else ConstVal.Value := 0;
  
  ConstValType := BOOLEANTYPEINDEX;
  end;

end;// CompileConstExpression




procedure CompilePredefinedProc(proc: TPredefProc; LoopNesting: Integer);


  function GetReadProcIdent(DataType: Integer): Integer;
  begin
  Result := 0;

  if (Types[DataType].Kind = INTEGERTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = INTEGERTYPE)) then
        Result := GetIdent('READINT')                 // Integer argument
        
  else if (Types[DataType].Kind = SMALLINTTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = SMALLINTTYPE)) then
        Result := GetIdent('READSMALLINT')            // Small integer argument
        
  else if (Types[DataType].Kind = SHORTINTTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = SHORTINTTYPE)) then
        Result := GetIdent('READSHORTINT')            // Short integer argument
        
  else if (Types[DataType].Kind = WORDTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = WORDTYPE)) then
        Result := GetIdent('READWORD')                // Word argument

  else if (Types[DataType].Kind = BYTETYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = BYTETYPE)) then
        Result := GetIdent('READBYTE')                // Byte argument
       
  else if (Types[DataType].Kind = BOOLEANTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = BOOLEANTYPE)) then
        Result := GetIdent('READBOOLEAN')             // Boolean argument
  
  else if (Types[DataType].Kind = CHARTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = CHARTYPE)) then
        Result := GetIdent('READCH')                  // Character argument
        
  else if Types[DataType].Kind = REALTYPE then
        Result := GetIdent('READREAL')                // Real argument
        
  else if (Types[DataType].Kind = ARRAYTYPE) and (Types[DataType].BaseType = CHARTYPEINDEX) then
        Result := GetIdent('READSTRING')              // String argument
        
  else
    Error('Incompatible types');
 
  end; // GetReadProcIdent
  
  
  
  function GetWriteProcIdent(DataType: Integer): Integer;
  begin
  Result := 0;
  
  if (Types[DataType].Kind in IntegerTypes) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind in IntegerTypes)) then
        Result := GetIdent('WRITEINTF')                 // Integer argument
        
  else if (Types[DataType].Kind = BOOLEANTYPE) or
    ((Types[DataType].Kind = SUBRANGETYPE) and (Types[Types[DataType].BaseType].Kind = BOOLEANTYPE)) then
        Result := GetIdent('WRITEBOOLEANF')             // Boolean argument
        
  else if Types[DataType].Kind = REALTYPE then
        Result := GetIdent('WRITEREALF')                // Real argument
        
  else if Types[DataType].Kind = POINTERTYPE then
        Result := GetIdent('WRITEPOINTERF')             // Pointer argument
        
  else if (Types[DataType].Kind = ARRAYTYPE) and (Types[DataType].BaseType = CHARTYPEINDEX) then
        Result := GetIdent('WRITESTRINGF')              // String argument
        
  else
    Error('Incompatible types');
  
  end; // GetWriteProcIdentIndex
  
 

var
  DesignatorType, FileVarType, ExpressionType, FormatterType: Integer;
  LibProcIdentIndex, ConsoleIndex: Integer;
  IsFirstParam: Boolean;
  
  
begin // CompilePredefinedProc
NextTok;

case proc of
  INCPROC, DECPROC:
    begin
    EatTok(OPARTOK);
    AssertIdent;
    CompileDesignator(DesignatorType, FALSE);
    GetCompatibleType(DesignatorType, INTEGERTYPEINDEX);
    GenerateIncDec(proc, TypeSize(DesignatorType));
    EatTok(CPARTOK);
    end;


  READPROC, READLNPROC:
    begin
    ConsoleIndex := GetIdent('STDINPUTFILE');
    FileVarType := ANYTYPEINDEX;
    IsFirstParam := TRUE;

    if Tok.Kind = OPARTOK then
      begin
      NextTok;
      repeat
        // 1st argument - file handle
        if FileVarType <> ANYTYPEINDEX then
          DuplicateStackTop
        else
          PushVarPtr(Ident[ConsoleIndex].Value, 
                     Ident[ConsoleIndex].Scope, 
                     BlockStackTop - Ident[ConsoleIndex].NestingLevel, 
                     Ident[ConsoleIndex].RelocType);

        // 2nd argument - stream handle
        PushConst(0);
        
        // 3rd argument - designator
        CompileDesignator(DesignatorType, FALSE);

        if Types[DesignatorType].Kind = FILETYPE then               // File handle
          begin
          if not IsFirstParam or ((proc = READLNPROC) and (Types[DesignatorType].BaseType <> ANYTYPEINDEX)) then
            Error('Incompatible types');            
          FileVarType := DesignatorType;          
          end
        else                                                        // Any input variable
          begin
          // Select input subroutine
          if (Types[FileVarType].Kind = FILETYPE) and (Types[FileVarType].BaseType <> ANYTYPEINDEX) then      // Read from typed file
            begin            
            GetCompatibleRefType(Types[FileVarType].BaseType, DesignatorType);
            
            // 4th argument - record length 
            PushConst(TypeSize(Types[FileVarType].BaseType));
 
            LibProcIdentIndex := GetIdent('READREC');
            end
          else                                                                                                // Read from text file 
            LibProcIdentIndex := GetReadProcIdent(DesignatorType);  
            
          // Call selected input subroutine. Interface: FileHandle; StreamHandle; var Designator [; Length]  
          GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
          end; // else

        IsFirstParam := FALSE;

        if Tok.Kind <> COMMATOK then Break;
        NextTok;
      until FALSE;
      
      EatTok(CPARTOK);
      end; // if OPARTOR
      
      
    // Add CR+LF, if necessary
    if proc = READLNPROC then
      begin
      // 1st argument - file handle
      if FileVarType <> ANYTYPEINDEX then
        DuplicateStackTop
      else
        PushVarPtr(Ident[ConsoleIndex].Value, 
                   Ident[ConsoleIndex].Scope, 
                   BlockStackTop - Ident[ConsoleIndex].NestingLevel, 
                   Ident[ConsoleIndex].RelocType);
        
      // 2nd argument - stream handle
      PushConst(0);  
      
      LibProcIdentIndex := GetIdent('READNEWLINE');      
      GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
      end;
      
    // Remove first 3 arguments if they correspond to a file variable 
    if FileVarType <> ANYTYPEINDEX then
      DiscardStackTop(3);

    end;// READPROC, READLNPROC


  WRITEPROC, WRITELNPROC:
    begin
    ConsoleIndex := GetIdent('STDOUTPUTFILE');
    FileVarType := ANYTYPEINDEX;
    IsFirstParam := TRUE;

    if Tok.Kind = OPARTOK then
      begin
      NextTok;
      repeat
        // 1st argument - file handle
        if FileVarType <> ANYTYPEINDEX then
          DuplicateStackTop
        else
          PushVarPtr(Ident[ConsoleIndex].Value, 
                     Ident[ConsoleIndex].Scope, 
                     BlockStackTop - Ident[ConsoleIndex].NestingLevel, 
                     Ident[ConsoleIndex].RelocType);

        // 2nd argument - stream handle
        PushConst(0);
        
        // 3rd argument - expression (for untyped/text files) or designator (for typed files)
        if (Types[FileVarType].Kind = FILETYPE) and (Types[FileVarType].BaseType <> ANYTYPEINDEX) then
          CompileDesignator(ExpressionType, FALSE)
        else
          CompileExpression(ExpressionType, TRUE);
        
        if Types[ExpressionType].Kind = FILETYPE then           // File handle
          begin
          if not IsFirstParam or ((proc = WRITELNPROC) and (Types[ExpressionType].BaseType <> ANYTYPEINDEX)) then
            Error('Incompatible types');
          FileVarType := ExpressionType;
          end
        else                                                    // Any output expression
          begin
          // 4th argument - minimum width
          if Tok.Kind = COLONTOK then
            begin
            if (Types[FileVarType].Kind = FILETYPE) and (Types[FileVarType].BaseType <> ANYTYPEINDEX) then
              Error('Format specifiers are not allowed for typed files');
              
            NextTok;
            CompileExpression(FormatterType, FALSE);
            GetCompatibleType(FormatterType, INTEGERTYPEINDEX);
            
            // 5th argument - number of decimal places
            if (Tok.Kind = COLONTOK) and (Types[ExpressionType].Kind = REALTYPE) then
              begin
              NextTok;
              CompileExpression(FormatterType, FALSE);
              GetCompatibleType(FormatterType, INTEGERTYPEINDEX);
              end
            else
              PushConst(0);
 
            end            
          else
            begin
            PushConst(0);
            PushConst(0);
            end;            
          
          // Select output subroutine
          if (Types[FileVarType].Kind = FILETYPE) and (Types[FileVarType].BaseType <> ANYTYPEINDEX) then      // Write to typed file                                                     
            begin           
            GetCompatibleRefType(Types[FileVarType].BaseType, ExpressionType);
            
            // Discard 4th and 5th arguments - format specifiers
            DiscardStackTop(2); 
  
            // 4th argument - record length 
            PushConst(TypeSize(Types[FileVarType].BaseType));
            
            LibProcIdentIndex := GetIdent('WRITEREC');
            end 
          else                                                                                                // Write to text file
            LibProcIdentIndex := GetWriteProcIdent(ExpressionType);
            
          // Call selected output subroutine. Interface: FileHandle; StreamHandle; (Designator | Expression); (Length; | MinWidth; DecPlaces)
          GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
          end; // else

        IsFirstParam := FALSE;

        if Tok.Kind <> COMMATOK then Break;
        NextTok;
      until FALSE;
      
      EatTok(CPARTOK);
      end; // if OPARTOR
      
      
    // Add CR+LF, if necessary
    if proc = WRITELNPROC then
      begin
      LibProcIdentIndex := GetIdent('WRITENEWLINE');
      
      // 1st argument - file handle
      if FileVarType <> ANYTYPEINDEX then
        DuplicateStackTop
      else
        PushVarPtr(Ident[ConsoleIndex].Value, 
                   Ident[ConsoleIndex].Scope, 
                   BlockStackTop - Ident[ConsoleIndex].NestingLevel, 
                   Ident[ConsoleIndex].RelocType);
        
      // 2nd argument - stream handle
      PushConst(0);         

      GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
      end;

    // Remove first 3 arguments if they correspond to a file variable 
    if FileVarType <> ANYTYPEINDEX then
      DiscardStackTop(3);
    
    end;// WRITEPROC, WRITELNPROC
    

  NEWPROC, DISPOSEPROC:
    begin
    EatTok(OPARTOK);
    AssertIdent;
    CompileDesignator(DesignatorType, FALSE);
    GetCompatibleType(DesignatorType, POINTERTYPEINDEX);
    
    if proc = NEWPROC then
      LibProcIdentIndex := GetIdent('GETMEM')
    else
      LibProcIdentIndex := GetIdent('FREEMEM');
      
    PushConst(TypeSize(Types[DesignatorType].BaseType));
    
    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
    
    EatTok(CPARTOK);
    end;
    
    
  BREAKPROC:
    begin
    if LoopNesting < 1 then
      Error('BREAK outside of loop is not allowed');
    GenerateBreakCall(LoopNesting);
    end;
  

  CONTINUEPROC:
    begin
    if LoopNesting < 1 then
      Error('CONTINUE outside of loop is not allowed');
    GenerateContinueCall(LoopNesting);
    end;
    
    
  EXITPROC:
    GenerateExitCall;
  

  HALTPROC:
    begin
    if Tok.Kind = OPARTOK then
      begin
      NextTok;
      CompileExpression(ExpressionType, FALSE);
      GetCompatibleType(ExpressionType, INTEGERTYPEINDEX);
      EatTok(CPARTOK);
      end
    else
      PushConst(0);
      
    LibProcIdentIndex := GetIdent('EXITPROCESS');
    InverseStack(Ident[LibProcIdentIndex].NumParams);
    GenerateCall(Ident[LibProcIdentIndex].Value, 1, 1);
    end;

end;// case

end;// CompilePredefinedProc




procedure CompilePredefinedFunc(func: TPredefProc; var ValType: Integer);
var
  IdentIndex: Integer;

begin
NextTok;
EatTok(OPARTOK);

case func of

  SIZEOFFUNC:
    begin
    AssertIdent;
    if FieldInsideWithFound(Tok.Name) then                // Record field inside a WITH block
      begin
      CompileDesignator(ValType, FALSE);
      DiscardStackTop(1);
      PushConst(TypeSize(ValType));      
      end
    else                                                  // Ordinary identifier
      begin  
      IdentIndex := GetIdent(Tok.Name);
      if Ident[IdentIndex].Kind = USERTYPE then
        begin
        NextTok;
        PushConst(TypeSize(Ident[IdentIndex].DataType));
        end
      else
        begin
        CompileDesignator(ValType, FALSE);
        DiscardStackTop(1);
        PushConst(TypeSize(ValType));
        end;
      end;
    ValType := INTEGERTYPEINDEX;
    end;
    

  ROUNDFUNC, TRUNCFUNC:
    begin
    CompileExpression(ValType, FALSE);

    // Try to convert integer to real
    if ConversionToRealIsPossible(ValType, REALTYPEINDEX) then
      begin
      GenerateFloat(0);
      ValType := REALTYPEINDEX;
      end;

    GetCompatibleType(ValType, REALTYPEINDEX);
    GenerateRound(func = TRUNCFUNC);
    ValType := INTEGERTYPEINDEX;
    end;
    

  ORDFUNC:
    begin
    CompileExpression(ValType, FALSE);
    if not (Types[ValType].Kind in OrdinalTypes) then
      Error('Ordinal type expected');
    ValType := INTEGERTYPEINDEX;
    end;
    

  CHRFUNC:
    begin
    CompileExpression(ValType, FALSE);
    GetCompatibleType(ValType, INTEGERTYPEINDEX);
    ValType := CHARTYPEINDEX;
    end;
    

  PREDFUNC, SUCCFUNC:
    begin
    CompileExpression(ValType, FALSE);
    if not (Types[ValType].Kind in OrdinalTypes) then
      Error('Ordinal type expected');
    if func = SUCCFUNC then
      PushConst(1)
    else
      PushConst(-1);
    GenerateBinaryOperator(PLUSTOK, INTEGERTYPEINDEX);
    end;
    

  ABSFUNC, SQRFUNC, SINFUNC, COSFUNC, ARCTANFUNC, EXPFUNC, LNFUNC, SQRTFUNC:
    begin
    CompileExpression(ValType, FALSE);
    if (func = ABSFUNC) or (func = SQRFUNC) then                          // Abs and Sqr accept real or integer parameters
      begin
      if not ((Types[ValType].Kind in NumericTypes) or
             ((Types[ValType].Kind = SUBRANGETYPE) and (Types[Types[ValType].BaseType].Kind in NumericTypes))) then
        Error('Numeric type expected')
      end
    else
      begin
      
      // Try to convert integer to real
      if ConversionToRealIsPossible(ValType, REALTYPEINDEX) then
        begin
        GenerateFloat(0);
        ValType := REALTYPEINDEX;
        end;

      GetCompatibleType(ValType, REALTYPEINDEX);
      end;

    GenerateMathFunction(func, ValType);
    end;
    
end;// case

EatTok(CPARTOK);
end;// CompilePredefinedFunc




procedure CompileTypeIdent(var DataType: Integer; AllowForwardReference: Boolean);
var
  IdentIndex: Integer;
begin
// STRING, FILE or type name allowed
case Tok.Kind of
  STRINGTOK:
    DataType := STRINGTYPEINDEX;
  FILETOK:
    DataType := FILETYPEINDEX
else
  AssertIdent;
  
  if AllowForwardReference then
    IdentIndex := GetIdentUnsafe(Tok.Name, AllowForwardReference)
  else
    IdentIndex := GetIdent(Tok.Name, AllowForwardReference);                         
  
  if AllowForwardReference and ((IdentIndex = 0) or (Ident[IdentIndex].Block <> BlockStack[BlockStackTop].Index)) then
    begin
    // Add new forward-referenced type
    Inc(NumTypes);
    if NumTypes > MAXTYPES then
      Error('Maximum number of types exceeded');    
    
    Types[NumTypes].Kind := FORWARDTYPE;
    Types[NumTypes].TypeIdentName := Tok.Name;
    Types[NumTypes].Block := BlockStack[BlockStackTop].Index;
    DataType := NumTypes;
    end
  else
    begin
    // Use existing type
    if Ident[IdentIndex].Kind <> USERTYPE then
      Error('Type name expected');
  
    DataType := Ident[IdentIndex].DataType;
    end;
end; // case

NextTok;
end; // CompileTypeIdent
  



procedure CompileFormalParametersAndResult(IsFunction: Boolean; var NumFormalParams, NumDefaultFormalParams: Integer; var FormalParam: PParams; var ResultType: Integer; var IsStdCall: Boolean);
var
  IdentInListName: array [1..MAXPARAMS] of TString;
  NumIdentInList, IdentInListIndex: Integer;  
  ParamType, DefaultValueType: Integer;    
  ListPassMethod: TPassMethod;
  IsOpenArrayList: Boolean;
  Default: TConst;
  
begin
NumFormalParams := 0;
NumDefaultFormalParams := 0;
  
if Tok.Kind = OPARTOK then
  begin
  NextTok;
  repeat
    NumIdentInList := 0;
    ListPassMethod := VALPASSING;

    if Tok.Kind = CONSTTOK then
      begin
      ListPassMethod := CONSTPASSING;
      NextTok;
      end
    else if Tok.Kind = VARTOK then
      begin
      ListPassMethod := VARPASSING;
      NextTok;
      end;

    repeat
      AssertIdent;

      Inc(NumIdentInList);
      IdentInListName[NumIdentInList] := Tok.Name;

      NextTok;

      if Tok.Kind <> COMMATOK then Break;
      NextTok;
    until FALSE;

    
    // Formal parameter list type
    if Tok.Kind = COLONTOK then                       // Typed parameters 
      begin
      NextTok;
    
      // Special case: open array parameters
      if Tok.Kind = ARRAYTOK then
        begin
        NextTok;
        EatTok(OFTOK);
        IsOpenArrayList := TRUE;
        end
      else
        IsOpenArrayList := FALSE;
 
      // Type itself
      CompileTypeIdent(ParamType, FALSE);          
                 
      // Special case: open array parameters
      if IsOpenArrayList then
        begin
        // Add new anonymous type 0..0 for array index
        Inc(NumTypes);
        if NumTypes > MAXTYPES then
          Error('Maximum number of types exceeded');
        
        Types[NumTypes].Kind        := SUBRANGETYPE;
        Types[NumTypes].Block       := BlockStack[BlockStackTop].Index;
        Types[NumTypes].BaseType    := INTEGERTYPEINDEX;
        Types[NumTypes].Low         := 0;
        Types[NumTypes].High        := 0;
        
        // Add new anonymous type for array itself
        Inc(NumTypes);
        if NumTypes > MAXTYPES then
          Error('Maximum number of types exceeded');
        
        Types[NumTypes].Kind        := ARRAYTYPE;
        Types[NumTypes].Block       := BlockStack[BlockStackTop].Index;
        Types[NumTypes].BaseType    := ParamType;
        Types[NumTypes].IndexType   := NumTypes - 1;
        Types[NumTypes].IsOpenArray := TRUE;
        
        ParamType := NumTypes;
        end;  
      end
    else                                              // Untyped parameters (CONST or VAR only) 
      ParamType := ANYTYPEINDEX;

    
    if (ListPassMethod = VALPASSING) and (Types[ParamType].Kind in StructuredTypes) then
      Error('Structured parameters cannot be passed by value');
      
    if (ListPassMethod = VALPASSING) and (ParamType = ANYTYPEINDEX) then
      Error('Untyped parameters cannot be passed by value');
      

    // Default parameter value
    if (Tok.Kind = EQTOK) or (NumDefaultFormalParams > 0) then
      begin
      EatTok(EQTOK);
      
      if not (Types[ParamType].Kind in OrdinalTypes + [REALTYPE]) then
        Error('Ordinal or real type expected for default parameter');
        
      if ListPassMethod <> VALPASSING then
        Error('Default parameters cannot be passed by reference');

      CompileConstExpression(Default, DefaultValueType);
      GetCompatibleType(ParamType, DefaultValueType);
        
      Inc(NumDefaultFormalParams);
      end;
      

    for IdentInListIndex := 1 to NumIdentInList do
      begin
      Inc(NumFormalParams);

      if NumFormalParams > MAXPARAMS then
        Error('Too many formal parameters');

      New(FormalParam[NumFormalParams]);

      FormalParam[NumFormalParams]^.DataType   := ParamType;
      FormalParam[NumFormalParams]^.PassMethod := ListPassMethod;
      FormalParam[NumFormalParams]^.Name       := IdentInListName[IdentInListIndex];
      
      // Default parameter value
      if (NumDefaultFormalParams > 0) and (IdentInListIndex = 1) then
        begin
        if NumIdentInList > 1 then
          Error('Default parameters cannot be grouped');          
        FormalParam[NumFormalParams]^.Default := Default; 
        end;
        
      end;// for
      

    if Tok.Kind <> SEMICOLONTOK then Break;
    NextTok;
  until FALSE;

  EatTok(CPARTOK);
  end;// if Tok.Kind = OPARTOR


// Function result type
ResultType := 0;

if IsFunction then
  begin
  EatTok(COLONTOK);  
  CompileTypeIdent(ResultType, FALSE);
  end;
  
  
// Call modifier
if (Tok.Kind = IDENTTOK) and (Tok.Name = 'STDCALL') then
  begin
  if IsFunction then
    if Types[ResultType].Kind in StructuredTypes then
      Error('STDCALL function cannot return structured result');
      
  IsStdCall := TRUE;
  NextTok;
  end
else  
  IsStdCall := FALSE;
  
end; // CompileFormalParametersAndResult




procedure CompileActualParameters(NumFormalParams, NumDefaultFormalParams: Integer; var FormalParam: PParams; ResultType: Integer);
var
  NumActualParams: Integer;
  ActualParamType: Integer;
  DefaultParamIndex: Integer;
  TempStorageAddr: Integer;
  IsRefParam: Boolean;
  CurParam: PParam;
  
begin
NumActualParams := 0;


if Tok.Kind = OPARTOK then                            // Actual parameter list found
  begin
  NextTok;
  
  if Tok.Kind <> CPARTOK then
    repeat
      if NumActualParams + 1 > NumFormalParams then
        Error('Too many actual parameters');

      CurParam := FormalParam[NumActualParams + 1];

      // Evaluate actual parameters and push them onto the stack
      if Types[CurParam^.DataType].Kind in StructuredTypes + [ANYTYPE] then
        IsRefParam := (CurParam^.PassMethod = CONSTPASSING) or
                      (CurParam^.PassMethod = VARPASSING)                   // For structured parameters, CONST is equivalent to VAR
      else
        IsRefParam := CurParam^.PassMethod = VARPASSING;                    // For scalar parameters, CONST is equivalent to passing by value

      if IsRefParam and (CurParam^.DataType <> STRINGTYPEINDEX) then
        CompileDesignator(ActualParamType, FALSE)
      else
        CompileExpression(ActualParamType, CurParam^.DataType = STRINGTYPEINDEX);

      Inc(NumActualParams);

      // Try to convert integer to real
      if ConversionToRealIsPossible(ActualParamType, CurParam^.DataType) and not IsRefParam then
        begin
        GenerateFloat(0);
        ActualParamType := REALTYPEINDEX;
        end;
      
      if IsRefParam then  // Strict type checking for parameters passed by reference, except for open array parameters and untyped parameters
        GetCompatibleRefType(CurParam^.DataType, ActualParamType)
      else                // Relaxed type checking for parameters passed by value      
        GetCompatibleType(CurParam^.DataType, ActualParamType);
        
    if Tok.Kind <> COMMATOK then Break;
    NextTok;
    until FALSE;

  EatTok(CPARTOK);
  end;// if Tok.Kind = OPARTOK
  

if NumActualParams < NumFormalParams - NumDefaultFormalParams then
  Error('Too few actual parameters');
  
  
// Push default parameters
for DefaultParamIndex := NumActualParams + 1 to NumFormalParams do
  begin
  CurParam := FormalParam[DefaultParamIndex];
  PushConst(CurParam^.Default.Value);
  end; // for  

  
// Allocate space for structured Result as a hidden VAR parameter
if ResultType <> 0 then
  if Types[ResultType].Kind in StructuredTypes then
    begin
    TempStorageAddr := AllocateTempStorage(TypeSize(ResultType));
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    end;
end;// CompileActualParameters




procedure CompileCall(IdentIndex: Integer);
var
  ResultType: Integer;
begin
if Ident[IdentIndex].Kind = FUNC then
  ResultType := Ident[IdentIndex].DataType
else  
  ResultType := 0;
  
CompileActualParameters(Ident[IdentIndex].NumParams, Ident[IdentIndex].NumDefaultParams, Ident[IdentIndex].Param, ResultType);

if Ident[IdentIndex].IsStdCall then
  InverseStack(Ident[IdentIndex].NumParams);
  
GenerateCall(Ident[IdentIndex].Value, BlockStackTop - 1, Ident[IdentIndex].NestingLevel);
end; // CompileCall




procedure CompileIndirectCall(ProcVarType: Integer; FunctionOnly: Boolean);
var
  TotalNumParams: Integer;
begin
if (Types[ProcVarType].Kind <> PROCEDURALTYPE) or (FunctionOnly and (Types[ProcVarType].ResultType = 0)) then 
  Error('Appropriate procedural variable expected'); 

DerefPtr(ProcVarType);

CompileActualParameters(Types[ProcVarType].NumParams, Types[ProcVarType].NumDefaultParams, Types[ProcVarType].Param, Types[ProcVarType].ResultType);

TotalNumParams := Types[ProcVarType].NumParams;
if Types[Types[ProcVarType].ResultType].Kind in StructuredTypes then
  Inc(TotalNumParams);  //   Allocate space for structured Result as a hidden VAR parameter

if Types[ProcVarType].IsStdCall then
  InverseStack(TotalNumParams);

GenerateIndirectCall(TotalNumParams);
end; // CompileIndirectCall




procedure CompileFieldInsideWith(var ValType: Integer);
var
  FieldIndex: Integer;
  RecType: Integer;
  TempStorageAddr: Integer;
begin 
ValType := 0;

FieldIndex := GetFieldInsideWith(TempStorageAddr, RecType, Tok.Name);
  
if FieldIndex <> 0 then
  begin
  PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
  DerefPtr(POINTERTYPEINDEX);
  
  GetFieldPtr(RecType, FieldIndex);
  ValType := Types[RecType].Field[FieldIndex]^.DataType;    
  end;
end; // CompileFieldInsideWith




procedure ConvertCharToString(var ValType: Integer; IsDesignator: Boolean);
var
  TempStorageAddr: LongInt;
begin
// Any character is converted into a 2-character temporary string
if (Types[ValType].Kind = CHARTYPE) or ((Types[ValType].Kind = SUBRANGETYPE) and (Types[Types[ValType].BaseType].Kind = CHARTYPE)) then
  begin
  if IsDesignator then
    DerefPtr(ValType);
  
  TempStorageAddr := AllocateTempStorage(2 * SizeOf(Char));    
  PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
  
  GetCharAsTempString;    
  ValType := STRINGTYPEINDEX;
  end;
end; // ConvertCharToString  




procedure CompileDesignator{(var ValType: Integer; ForceCharToString: Boolean)};
var
  IdentIndex, FieldIndex: Integer;
  ArrayIndexType: Integer;  
  IsRefParam: Boolean;
  
begin
AssertIdent;

// First search among records in WITH blocks
CompileFieldInsideWith(ValType);

// If unsuccessful, search among ordinary variables
if ValType = 0 then
  begin
  IdentIndex := GetIdent(Tok.Name);

  if Ident[IdentIndex].Kind <> VARIABLE then
    Error('Variable expected but ' + GetTokSpelling(Tok.Kind) + ' found');
    
  PushVarPtr(Ident[IdentIndex].Value, 
             Ident[IdentIndex].Scope, 
             BlockStackTop - Ident[IdentIndex].NestingLevel, 
             Ident[IdentIndex].RelocType);
  
  ValType := Ident[IdentIndex].DataType;           
  
  if ForceCharToString then
    ConvertCharToString(ValType, TRUE);

  if Types[Ident[IdentIndex].DataType].Kind in StructuredTypes + [ANYTYPE] then
    IsRefParam := Ident[IdentIndex].PassMethod in [CONSTPASSING, VARPASSING]    // For structured parameters, CONST is equivalent to VAR
  else
    IsRefParam := Ident[IdentIndex].PassMethod = VARPASSING;                    // For scalar parameters, CONST is equivalent to passing by value

  if IsRefParam then DerefPtr(POINTERTYPEINDEX);                                // Parameter is passed by reference
  end; // if

  
// Apply dereferencing, indexing, field accessing
NextTok;

while Tok.Kind in [DEREFERENCETOK, OBRACKETTOK, PERIODTOK] do
  begin
  case Tok.Kind of
  
    DEREFERENCETOK:                                   // Pointer dereferencing
      begin
      if (Types[ValType].Kind <> POINTERTYPE) or (Types[ValType].BaseType = ANYTYPEINDEX) then
        Error('Typed pointer expected');
      DerefPtr(ValType);
      ValType := Types[ValType].BaseType;
      NextTok;
      end;
    
    OBRACKETTOK:                                      // Array element access
      begin
      repeat
        if Types[ValType].Kind <> ARRAYTYPE then
          Error('Array expected');
        NextTok;
        CompileExpression(ArrayIndexType, FALSE);     // Array index
        GetCompatibleType(ArrayIndexType, Types[ValType].IndexType);
        GetArrayElementPtr(ValType);
        ValType := Types[ValType].BaseType;
      until Tok.Kind <> COMMATOK;
      EatTok(CBRACKETTOK);
      end;
      
    PERIODTOK:                                        // Record field access
      begin
      if Types[ValType].Kind <> RECORDTYPE then
        Error('Record expected');
      NextTok;
      AssertIdent;
      FieldIndex := GetField(ValType, Tok.Name);
      GetFieldPtr(ValType, FieldIndex);
      ValType := Types[ValType].Field[FieldIndex]^.DataType;
      NextTok;   
      end;
    
  end; // case
  
  if ForceCharToString then
    ConvertCharToString(ValType, TRUE);
  end; // while  
  
end; // CompileDesignator




procedure CompileSetConstructor(var ValType: Integer);
var
  ElementType: Integer;
  LibProcIdentIndex: Integer;
  TempStorageAddr: Integer;
  
begin
// Add new anonymous type
Inc(NumTypes);
if NumTypes > MAXTYPES then
  Error('Maximum number of types exceeded');

Types[NumTypes].Kind := SETTYPE;
Types[NumTypes].Block := BlockStack[BlockStackTop].Index;
Types[NumTypes].BaseType := ANYTYPEINDEX;
ValType := NumTypes;

// Allocate temporary storage
TempStorageAddr := AllocateTempStorage(TypeSize(ValType));
PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);

// Initialize set
LibProcIdentIndex := GetIdent('INITSET');
GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel); 

// Compile constructor
LibProcIdentIndex := GetIdent('ADDTOSET');
NextTok;

if Tok.Kind <> CBRACKETTOK then
  repeat
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    
    CompileExpression(ElementType, FALSE);
    
    if Types[ValType].BaseType = ANYTYPEINDEX then
      begin
      if not (Types[ElementType].Kind in OrdinalTypes) then
        Error('Ordinal type expected');        
      Types[ValType].BaseType := ElementType;
      end  
    else  
      GetCompatibleType(ElementType, Types[ValType].BaseType);

    if Tok.Kind = RANGETOK then
      begin
      NextTok;
      CompileExpression(ElementType, FALSE);    
      GetCompatibleType(ElementType, Types[ValType].BaseType);
      end
    else
      PushConst(-1);
      
    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);        
      
    if Tok.Kind <> COMMATOK then Break;
    NextTok;
  until FALSE;
  
EatTok(CBRACKETTOK);

PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
end; // CompileSetConstructor




procedure CompileFactor(var ValType: Integer; ForceCharToString: Boolean);


  procedure CompileDereferenceOrCall(var ValType: Integer);
  begin
  if Tok.Kind = OPARTOK then                     // Procedural variable call - parentheses required even for empty parameter list
    begin
    CompileIndirectCall(ValType, TRUE);
    RestoreStackTopFromEAX;
    ValType := Types[ValType].ResultType;
    end       
  else                                           // Usual variable
    if not (Types[ValType].Kind in StructuredTypes) then // Factors of type 'array', 'record', 'set' should contain a pointer to them
      DerefPtr(ValType);
  end; // CompileDereferenceOrCall
  
  
var
  IdentIndex: Integer;
  NotOpTok: TToken;

  
begin // CompileFactor
case Tok.Kind of

  IDENTTOK:
    if FieldInsideWithFound(Tok.Name) then                                              // Record field inside a WITH block
      begin
      CompileDesignator(ValType, ForceCharToString);
      CompileDereferenceOrCall(ValType);
      end      
    else                                                                                // Ordinary identifier
      begin
      IdentIndex := GetIdent(Tok.Name);

      case Ident[IdentIndex].Kind of
      
        GOTOLABEL:
          Error('Expression expected but label ' + Ident[IdentIndex].Name + ' found');
      
        PROC:
          Error('Expression expected but procedure ' + Ident[IdentIndex].Name + ' found');
          
        FUNC:                                                                           // Function call
          if Ident[IdentIndex].PredefProc <> EMPTYPROC then                                    // Predefined function call
            CompilePredefinedFunc(Ident[IdentIndex].PredefProc, ValType)
          else                                                                          // User-defined function call
            begin
            NextTok;
            CompileCall(IdentIndex);
            RestoreStackTopFromEAX;
            ValType := Ident[IdentIndex].DataType;
            end;
            
        VARIABLE:                                                                       // Designator
          begin
          CompileDesignator(ValType, ForceCharToString);
          CompileDereferenceOrCall(ValType);   
          end;
          
        CONSTANT:                                                                       // Constant
          begin
          ValType := Ident[IdentIndex].DataType;
          PushConst(Ident[IdentIndex].Value);
          NextTok;
          end;
          
        USERTYPE:                                                                       // Type cast
          begin                                                                      
          NextTok;
          EatTok(OPARTOK);
          CompileExpression(ValType, FALSE);
          EatTok(CPARTOK);

          if not ((Types[Ident[IdentIndex].DataType].Kind in CastableTypes) and 
                  (Types[ValType].Kind in CastableTypes)) then
            Error('Invalid typecast');

          ValType := Ident[IdentIndex].DataType;
          end
          
      else
        Error('Internal fault: Illegal identifier');  
      end; // case Ident[IdentIndex].Kind
      end; // else  


  ADDRESSTOK:
    begin
    NextTok;
    
    if FieldInsideWithFound(Tok.Name) then                  // Record field inside a WITH block
      CompileDesignator(ValType, FALSE)
    else                                                    // Ordinary identifier
      begin  
      IdentIndex := GetIdent(Tok.Name);
      
      if Ident[IdentIndex].Kind in [PROC, FUNC] then
        begin
        if (Ident[IdentIndex].PredefProc <> EMPTYPROC) or (Ident[IdentIndex].Block <> 1) then
          Error('Procedure or function cannot be predefined or nested');
          
        PushRelocConst(Ident[IdentIndex].Value, CODERELOC); // To be resolved later when code section origin is known        
        NextTok;
        end
      else  
        CompileDesignator(ValType, FALSE);
      end;  
      
    ValType := POINTERTYPEINDEX;
    end;


  INTNUMBERTOK:
    begin
    PushConst(Tok.Value);
    ValType := INTEGERTYPEINDEX;
    NextTok;
    end;


  FRACNUMBERTOK:
    begin
    PushConst(Tok.Value);
    ValType := REALTYPEINDEX;
    NextTok;
    end;


  CHARLITERALTOK:
    begin
    PushConst(Tok.Value);
    ValType := CHARTYPEINDEX;
    NextTok;
    end;


  STRINGLITERALTOK:
    begin
    PushVarPtr(Tok.StrAddress, GLOBAL, 0, INITDATARELOC);
    ValType := STRINGTYPEINDEX;
    NextTok;
    end;


  OPARTOK:       // Expression in parentheses expected
    begin
    NextTok;
    CompileExpression(ValType, ForceCharToString);
    EatTok(CPARTOK);
    end;


  NOTTOK:
    begin
    NotOpTok := Tok;
    NextTok;
    CompileFactor(ValType, ForceCharToString);
    CheckOperator(NotOpTok, ValType);
    GenerateUnaryOperator(NOTTOK, ValType);
    end;
    
    
  OBRACKETTOK:  
    CompileSetConstructor(ValType);
    

  NILTOK:
    begin
    PushConst(0);
    ValType := POINTERTYPEINDEX;
    NextTok;
    end

else
  Error('Expression expected but ' + GetTokSpelling(Tok.Kind) + ' found');
end;// case

if ForceCharToString then
  ConvertCharToString(ValType, FALSE);
end;// CompileFactor




procedure CompileTerm(var ValType: Integer; ForceCharToString: Boolean);
var
  OpTok: TToken;
  RightValType: Integer;
  LibProcIdentIndex: Integer;
  TempStorageAddr: Integer;
  UseShortCircuit: Boolean; 
  
begin
CompileFactor(ValType, ForceCharToString);

while Tok.Kind in MultiplicativeOperators do
  begin
  OpTok := Tok;
  NextTok;
  
  UseShortCircuit := (OpTok.Kind = ANDTOK) and (Types[ValType].Kind = BOOLEANTYPE);
  if UseShortCircuit then 
    GenerateShortCircuitProlog(OpTok.Kind);  
  
  CompileFactor(RightValType, ForceCharToString);

  // Try to convert integer to real
  if ConversionToRealIsPossible(ValType, RightValType) then
    begin
    GenerateFloat(SizeOf(Single));
    ValType := REALTYPEINDEX;
    end;
  if ConversionToRealIsPossible(RightValType, ValType) then
    begin
    GenerateFloat(0);
    RightValType := REALTYPEINDEX;
    end;

  // Special case: real division of two integers
  if (OpTok.Kind = DIVTOK) and ConversionToRealIsPossible(ValType, REALTYPEINDEX) and ConversionToRealIsPossible(RightValType, REALTYPEINDEX) then
    begin
    GenerateFloat(SizeOf(Single));
    GenerateFloat(0);
    ValType := REALTYPEINDEX;
    RightValType := REALTYPEINDEX;
    end;
    
  // Special case: set intersection  
  if (OpTok.Kind = MULTOK) and (Types[ValType].Kind = SETTYPE) then  
    begin
    ValType := GetCompatibleType(ValType, RightValType);
    
    LibProcIdentIndex := GetIdent('SETINTERSECTION');
      
    TempStorageAddr := AllocateTempStorage(TypeSize(ValType));    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);

    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    end
  // General rule  
  else
    begin
    ValType := GetCompatibleType(ValType, RightValType);
    CheckOperator(OpTok, ValType);

    if UseShortCircuit then 
      GenerateShortCircuitEpilog
    else 
      GenerateBinaryOperator(OpTok.Kind, ValType);
    end;
    
  end;// while

end;// CompileTerm




procedure CompileSimpleExpression(var ValType: Integer; ForceCharToString: Boolean);
var
  UnaryOpTok, OpTok: TToken;
  RightValType: Integer;
  LibProcIdentIndex: Integer;
  TempStorageAddr: Integer;
  UseShortCircuit: Boolean; 
  
begin
UnaryOpTok := Tok;
if UnaryOpTok.Kind in UnaryOperators then
  NextTok;

CompileTerm(ValType, ForceCharToString);

if UnaryOpTok.Kind in UnaryOperators then
  CheckOperator(UnaryOpTok, ValType);

if UnaryOpTok.Kind = MINUSTOK then GenerateUnaryOperator(MINUSTOK, ValType);     // Unary minus

while Tok.Kind in AdditiveOperators do
  begin
  OpTok := Tok;
  NextTok;
  
  UseShortCircuit := (OpTok.Kind = ORTOK) and (Types[ValType].Kind = BOOLEANTYPE);
  if UseShortCircuit then 
    GenerateShortCircuitProlog(OpTok.Kind);
  
  CompileTerm(RightValType, ForceCharToString); 

  // Try to convert integer to real
  if ConversionToRealIsPossible(ValType, RightValType) then
    begin
    GenerateFloat(SizeOf(Single));
    ValType := REALTYPEINDEX;
    end;
  if ConversionToRealIsPossible(RightValType, ValType) then
    begin
    GenerateFloat(0);
    RightValType := REALTYPEINDEX;
    end;
      
  // Special case: string concatenation
  if (ValType = STRINGTYPEINDEX) and (RightValType = STRINGTYPEINDEX) and (OpTok.Kind = PLUSTOK) then
    begin 
    LibProcIdentIndex := GetIdent('CONCATSTR');   

    TempStorageAddr := AllocateTempStorage(TypeSize(STRINGTYPEINDEX));    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    
    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    ValType := STRINGTYPEINDEX;
    end
  // Special case: set union or difference  
  else if (OpTok.Kind in [PLUSTOK, MINUSTOK]) and (Types[ValType].Kind = SETTYPE) then  
    begin
    ValType := GetCompatibleType(ValType, RightValType);
    
    if OpTok.Kind = PLUSTOK then
      LibProcIdentIndex := GetIdent('SETUNION')
    else
      LibProcIdentIndex := GetIdent('SETDIFFERENCE');
      
    TempStorageAddr := AllocateTempStorage(TypeSize(ValType));    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);

    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    end  
  // General rule
  else
    begin
    ValType := GetCompatibleType(ValType, RightValType);
    CheckOperator(OpTok, ValType);
 
    if UseShortCircuit then 
      GenerateShortCircuitEpilog
    else 
      GenerateBinaryOperator(OpTok.Kind, ValType);
    end;
  
  end;// while

end;// CompileSimpleExpression




procedure CompileExpression{(var ValType: Integer; ForceCharToString: Boolean)};
var
  OpTok: TToken;
  RightValType: Integer;
  LibProcIdentIndex: Integer;

  
begin // CompileExpression
CompileSimpleExpression(ValType, ForceCharToString);

if Tok.Kind in RelationOperators then
  begin
  OpTok := Tok;
  NextTok;
  CompileSimpleExpression(RightValType, ForceCharToString);

  // Try to convert integer to real
  if ConversionToRealIsPossible(ValType, RightValType) then
    begin
    GenerateFloat(SizeOf(Single));
    ValType := REALTYPEINDEX;
    end;
  if ConversionToRealIsPossible(RightValType, ValType) then
    begin
    GenerateFloat(0);
    RightValType := REALTYPEINDEX;
    end;
    
  // Special case: string comparison
  if (ValType = STRINGTYPEINDEX) and (RightValType = STRINGTYPEINDEX) then
    begin 
    LibProcIdentIndex := GetIdent('COMPARESTR');
   
    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
    RestoreStackTopFromEAX;
    ValType := Ident[LibProcIdentIndex].DataType;
    
    PushConst(0);
    RightValType := INTEGERTYPEINDEX;
    end;

  // Special case: set comparison
  if (OpTok.Kind in [EQTOK, NETOK, GETOK, LETOK]) and (Types[ValType].Kind = SETTYPE) then
    begin
    GetCompatibleType(ValType, RightValType); 
    
    case OpTok.Kind of
      GETOK: LibProcIdentIndex := GetIdent('TESTSUPERSET');    // Returns  1 if Val >= RightVal, -1 otherwise 
      LETOK: LibProcIdentIndex := GetIdent('TESTSUBSET')       // Returns -1 if Val <= RightVal,  1 otherwise 
      else   LibProcIdentIndex := GetIdent('COMPARESETS');     // Returns  0 if Val  = RightVal,  1 otherwise  
    end; 
    
    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
    RestoreStackTopFromEAX;
    ValType := Ident[LibProcIdentIndex].DataType;
    
    PushConst(0);  
    RightValType := INTEGERTYPEINDEX;
    end;  

  GetCompatibleType(ValType, RightValType);
  CheckOperator(OpTok, ValType);
  ValType := BOOLEANTYPEINDEX;
  GenerateRelation(OpTok.Kind, RightValType);
  end
else if Tok.Kind = INTOK then
  begin
  NextTok;
  CompileSimpleExpression(RightValType, ForceCharToString);
  
  if Types[RightValType].Kind <> SETTYPE then
    Error('Set expected');
  
  if Types[RightValType].BaseType <> ANYTYPEINDEX then
    GetCompatibleType(ValType, Types[RightValType].BaseType)
  else if not (Types[ValType].Kind in OrdinalTypes) then
    Error('Ordinal type expected');   

  LibProcIdentIndex := GetIdent('INSET');
  GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);
  RestoreStackTopFromEAX;
  ValType := Ident[LibProcIdentIndex].DataType;  
  end;  

end;// CompileExpression




procedure CompileStatementList(LoopNesting: Integer);
begin
CompileStatement(LoopNesting);
while Tok.Kind = SEMICOLONTOK do
  begin
  NextTok;
  CompileStatement(LoopNesting);
  end;
end; // CompileStatementList 




procedure CompileCompoundStatement(LoopNesting: Integer);
begin
EatTok(BEGINTOK);
CompileStatementList(LoopNesting);
EatTok(ENDTOK);
end; // CompileCompoundStatement




procedure CompileStatement{(LoopNesting: Integer)};



  procedure CompileLabel;
  var
    LabelIndex: Integer;
  begin
  if Tok.Kind = IDENTTOK then
    begin
    LabelIndex := GetIdentUnsafe(Tok.Name);
    
    if LabelIndex <> 0 then
      if Ident[LabelIndex].Kind = GOTOLABEL then
        begin
        if Ident[LabelIndex].Block <> BlockStack[BlockStackTop].Index then
          Error('Label is not declared in current procedure');
        
        Ident[LabelIndex].Value := GetCodeSize;        
        Ident[LabelIndex].IsUnresolvedForward := FALSE;
        Ident[LabelIndex].ForLoopNesting := ForLoopNesting;
        
        NextTok;
        EatTok(COLONTOK);
        end;      
    end;
  end; // CompileLabel
  
  
  
  
  procedure CompileAssignment(DesignatorType: Integer);
  var
    ExpressionType: Integer;
  begin
  NextTok;

  CompileExpression(ExpressionType, DesignatorType = STRINGTYPEINDEX);                          // General rule: right-hand side expression

  // Try to convert integer to real
  if ConversionToRealIsPossible(ExpressionType, DesignatorType) then
    begin
    GenerateFloat(0);
    ExpressionType := REALTYPEINDEX;
    end;

  GetCompatibleType(DesignatorType, ExpressionType);

  if Types[DesignatorType].Kind in StructuredTypes then
    GenerateStructuredAssignment(DesignatorType)
  else
    GenerateAssignment(DesignatorType);
  
  end; // CompileAssignment
  
  
  
  
  procedure CompileAssignmentOrCall(DesignatorType: Integer);
  begin 
  if Tok.Kind = ASSIGNTOK then                                    // Assignment
    CompileAssignment(DesignatorType)
  else                                                            // Procedural variable call                                                              
    begin
    CheckTok(OPARTOK);                                            // Parentheses required even for empty parameter list         
    CompileIndirectCall(DesignatorType, FALSE);
    end;  
  end; // CompileAssignmentOrCall
  

  
  
  procedure CompileIfStatement(LoopNesting: Integer);
  var
    ExpressionType: Integer;
    
  begin
  NextTok;
  
  CompileExpression(ExpressionType, FALSE);
  GetCompatibleType(ExpressionType, BOOLEANTYPEINDEX);
  
  EatTok(THENTOK);

  GenerateIfCondition;              // Satisfied if expression is not zero
  GenerateIfProlog;
  CompileStatement(LoopNesting);

  if Tok.Kind = ELSETOK then
    begin
    NextTok;
    GenerateElseProlog;                 
    CompileStatement(LoopNesting);
    end;

  GenerateIfElseEpilog;
  end; // CompileIfStatement  



  
  procedure CompileCaseStatement(LoopNesting: Integer);
  var
    SelectorType, ConstValType: Integer;
    NumCaseStatements: Integer;
    ConstVal, ConstVal2: TConst;
    
  begin
  NextTok;
  
  CompileExpression(SelectorType, FALSE);
  if not (Types[SelectorType].Kind in OrdinalTypes) then
    Error('Ordinal variable expected as CASE selector');
  
  EatTok(OFTOK);

  GenerateCaseProlog;  

  NumCaseStatements := 0;

  repeat       // Loop over all cases

    repeat     // Loop over all constants for the current case
      CompileConstExpression(ConstVal, ConstValType);
      GetCompatibleType(ConstValType, SelectorType);

      if Tok.Kind = RANGETOK then                                      // Range check
        begin
        NextTok;
        CompileConstExpression(ConstVal2, ConstValType);
        GetCompatibleType(ConstValType, SelectorType);
        GenerateCaseRangeCheck(ConstVal.Value, ConstVal2.Value);
        end
      else
        GenerateCaseEqualityCheck(ConstVal.Value);                     // Equality check

      if Tok.Kind <> COMMATOK then Break;
      NextTok;
    until FALSE;

    EatTok(COLONTOK);

    GenerateCaseStatementProlog;
    CompileStatement(LoopNesting);
    GenerateCaseStatementEpilog;

    Inc(NumCaseStatements);

    if Tok.Kind <> SEMICOLONTOK then
      begin
      if Tok.Kind = ELSETOK then              // Default statements
        begin
        NextTok;
        CompileStatementList(LoopNesting);
        end;          
      Break;
      end;

    NextTok;
  until Tok.Kind = ENDTOK;

  EatTok(ENDTOK);

  GenerateCaseEpilog(NumCaseStatements);
  end; // CompileCaseStatement
  
  
  
  
  procedure CompileWhileStatement(LoopNesting: Integer);
  var
    ExpressionType: Integer;
    
  begin
  SaveCodePos;      // Save return address used by GenerateWhileEpilog

  NextTok;
  CompileExpression(ExpressionType, FALSE);
  GetCompatibleType(ExpressionType, BOOLEANTYPEINDEX);
  
  EatTok(DOTOK);

  GenerateBreakProlog(LoopNesting);
  GenerateContinueProlog(LoopNesting);
  GenerateWhileCondition;                         // Satisfied if expression is not zero
  GenerateWhileProlog;
  
  CompileStatement(LoopNesting);
  
  GenerateContinueEpilog(LoopNesting);
  GenerateWhileEpilog;
  GenerateBreakEpilog(LoopNesting);
  end; // CompileWhileStatement
  
  
  
  
  procedure CompileRepeatStatement(LoopNesting: Integer);
  var
    ExpressionType: Integer;
    
  begin
  GenerateBreakProlog(LoopNesting);
  GenerateContinueProlog(LoopNesting);
  GenerateRepeatProlog;

  NextTok;
  CompileStatementList(LoopNesting);

  EatTok(UNTILTOK);
  
  GenerateContinueEpilog(LoopNesting);

  CompileExpression(ExpressionType, FALSE);
  GetCompatibleType(ExpressionType, BOOLEANTYPEINDEX);
  
  GenerateRepeatCondition;
  GenerateRepeatEpilog;
  GenerateBreakEpilog(LoopNesting);
  end; // CompileRepeatStatement
  
  
  
  
  procedure CompileForStatement(LoopNesting: Integer);
  var
    CounterIndex: Integer;
    ExpressionType: Integer;
    Down: Boolean;
      
  begin
  NextTok;
  
  AssertIdent;
  CounterIndex := GetIdent(Tok.Name);

  if (Ident[CounterIndex].Kind <> VARIABLE) or
    ((Ident[CounterIndex].NestingLevel <> 1) and (Ident[CounterIndex].NestingLevel <> BlockStackTop)) or
     (Ident[CounterIndex].PassMethod <> VALPASSING) then
    Error('Simple local variable expected as FOR loop counter');

  if not (Types[Ident[CounterIndex].DataType].Kind in OrdinalTypes) then
    Error('Ordinal variable expected as FOR loop counter');
    
  PushVarPtr(Ident[CounterIndex].Value, Ident[CounterIndex].Scope, 0, Ident[CounterIndex].RelocType);
  
  NextTok;
  EatTok(ASSIGNTOK);
  
  // Initial counter value
  CompileExpression(ExpressionType, FALSE);
  GetCompatibleType(ExpressionType, Ident[CounterIndex].DataType);  

  // Two instances of initial value: one for computing the number of iterations, another for assignment to the counter
  DuplicateStackTop;

  if not (Tok.Kind in [TOTOK, DOWNTOTOK]) then
    CheckTok(TOTOK);

  Down := Tok.Kind = DOWNTOTOK;
  NextTok;
  
  // Final counter value
  CompileExpression(ExpressionType, FALSE);
  GetCompatibleType(ExpressionType, Ident[CounterIndex].DataType);
  
  // Compute and save the total number of iterations
  GenerateForNumberOfIterations(Down);
  
  // Assign initial value to the counter
  GenerateForAssignment(Ident[CounterIndex].DataType);
  
  // Save return address used by GenerateForEpilog
  SaveCodePos;
  
  // Check the remaining number of iterations
  GenerateForCondition;

  EatTok(DOTOK);
  
  GenerateBreakProlog(LoopNesting);
  GenerateContinueProlog(LoopNesting);
  GenerateForProlog;
  
  CompileStatement(LoopNesting);    
  
  GenerateContinueEpilog(LoopNesting);
  
  PushVarPtr(Ident[CounterIndex].Value, 
             Ident[CounterIndex].Scope, 
             0, 
             Ident[CounterIndex].RelocType);
             
  GenerateForEpilog(Ident[CounterIndex].DataType, Down);
  GenerateBreakEpilog(LoopNesting);
  
  // Pop and discard the remaining number of iterations (i.e. zero)
  DiscardStackTop(1);                                          
  end; // CompileForStatement

  
  
  
  procedure CompileGotoStatement(LoopNesting: Integer);
  var
    LabelIndex: Integer;
    
  begin
  NextTok;
  
  AssertIdent;
  LabelIndex := GetIdent(Tok.Name);
  
  if Ident[LabelIndex].Kind <> GOTOLABEL then
    Error('Label expected');
    
  if Ident[LabelIndex].Block <> BlockStack[BlockStackTop].Index then
    Error('Label is not declared in current procedure');
    
  GenerateGoto(LabelIndex);

  NextTok;
  end; // CompileGotoStatement



  
  procedure CompileWithStatement(LoopNesting: Integer);
  var
    DesignatorType: Integer;
    DeltaWithNesting: Integer;
    TempStorageAddr: Integer;
    
  begin
  NextTok;  
  DeltaWithNesting := 0; 

  repeat   
    // Save designator pointer to temporary storage
    TempStorageAddr := AllocateTempStorage(TypeSize(POINTERTYPEINDEX));    
    PushVarPtr(TempStorageAddr, LOCAL, 0, UNINITDATARELOC);
    
    CompileDesignator(DesignatorType, FALSE);
    if Types[DesignatorType].Kind <> RECORDTYPE then
      Error('Record expected');
      
    GenerateAssignment(POINTERTYPEINDEX);

    // Save designator info
    Inc(DeltaWithNesting);
    Inc(WithNesting);
    
    if WithNesting > MAXWITHNESTING then
      Error('Maximum WITH block nesting exceeded');
    
    WithStack[WithNesting].TempPointer := TempStorageAddr;
    WithStack[WithNesting].DataType := DesignatorType;    
    
    if Tok.Kind <> COMMATOK then Break;
    NextTok;
  until FALSE;
  
  EatTok(DOTOK);
  
  CompileStatement(LoopNesting);
  
  WithNesting := WithNesting - DeltaWithNesting;
  end; // CompileWithStatement
  
  
  
  
  function IsCurrentOrOuterFunc(FuncIdentIndex: Integer): Boolean;
  var
    BlockStackIndex: Integer;
  begin
  if Ident[FuncIdentIndex].Kind = FUNC then
    for BlockStackIndex := BlockStackTop downto 1 do
      if BlockStack[BlockStackIndex].Index = Ident[FuncIdentIndex].ProcAsBlock then
          begin
          Result := TRUE;
          Exit;
          end;        
  Result := FALSE;
  end; // IsCurrentOrOuterFunc



  
var
  IdentIndex: Integer;
  DesignatorType: Integer;

  
begin // CompileStatement
CompileLabel;

case Tok.Kind of

  IDENTTOK:
    begin   
    if FieldInsideWithFound(Tok.Name) then                              // Record field inside a WITH block
      begin
      CompileDesignator(DesignatorType, FALSE);
      CompileAssignmentOrCall(DesignatorType);
      end 
    else                                                                // Ordinary identifier                                                                                
      begin  
      IdentIndex := GetIdent(Tok.Name);
      
      case Ident[IdentIndex].Kind of
      
        VARIABLE:                                                       // Assignment or procedural variable call
          begin
          CompileDesignator(DesignatorType, FALSE);
          CompileAssignmentOrCall(DesignatorType); 
          end; // VARIABLE        

        PROC, FUNC:                                                     // Procedure or function call (returned result discarded)
          if Ident[IdentIndex].PredefProc <> EMPTYPROC then             // Predefined procedure
            begin
            if Ident[IdentIndex].Kind <> PROC then
              Error('Procedure expected but predefined function ' + Ident[IdentIndex].Name + ' found');            
            CompilePredefinedProc(Ident[IdentIndex].PredefProc, LoopNesting)
            end
          else                                                          // User-defined procedure or function
            begin
            NextTok;
            
            if Tok.Kind = ASSIGNTOK then                                // Special case: assignment to a function name
              begin
              if not IsCurrentOrOuterFunc(IdentIndex) then
                Error('Function name expected but ' + Ident[IdentIndex].Name + ' found');

              // Push pointer to Result
              PushVarPtr(Ident[Ident[IdentIndex].ResultIdentIndex].Value, 
                         LOCAL, 
                         BlockStackTop - Ident[Ident[IdentIndex].ResultIdentIndex].NestingLevel, 
                         UNINITDATARELOC);
              
              DesignatorType := Ident[Ident[IdentIndex].ResultIdentIndex].DataType;
              if Types[DesignatorType].Kind in StructuredTypes then 
                DerefPtr(POINTERTYPEINDEX);                        

              CompileAssignment(DesignatorType);
              end
            else                                                        // General rule: procedure or function call  
              CompileCall(IdentIndex);
              
            end  
              
      else
        Error('Statement expected but ' + Ident[IdentIndex].Name + ' found');
      end // case Ident[IdentIndex].Kind
      end; // else
    end;    

  BEGINTOK:
    CompileCompoundStatement(LoopNesting);    

  IFTOK:
    CompileIfStatement(LoopNesting);    

  CASETOK:
    CompileCaseStatement(LoopNesting);  

  WHILETOK:
    CompileWhileStatement(LoopNesting + 1);

  REPEATTOK:
    CompileRepeatStatement(LoopNesting + 1);    

  FORTOK:
    CompileForStatement(LoopNesting + 1);
    
  GOTOTOK:
    CompileGotoStatement(LoopNesting);

  WITHTOK:
    CompileWithStatement(LoopNesting);

end;// case

end;// CompileStatement




procedure CompileType{(var DataType: Integer)};


  procedure CompileEnumeratedType(var DataType: Integer);
  var
    ConstIndex: Integer;
  begin
  // Add new anonymous type
  Inc(NumTypes);
  if NumTypes > MAXTYPES then
    Error('Maximum number of types exceeded');
    
  Types[NumTypes].Kind := ENUMERATEDTYPE;
  DataType := NumTypes;

  // Compile enumeration constants
  ConstIndex := 0;
  NextTok;
  
  repeat
    AssertIdent;
    DeclareIdent(Tok.Name, CONSTANT, 0, DataType, VALPASSING, ConstIndex, 0.0, EMPTYPROC);
    
    Inc(ConstIndex);
    if ConstIndex > MAXENUMELEMENTS - 1 then
      Error('Too many enumeration elements');
      
    NextTok;
    
    if Tok.Kind <> COMMATOK then Break;
    NextTok;
  until FALSE;
  
  EatTok(CPARTOK);
  
  Types[DataType].Block := BlockStack[BlockStackTop].Index;
  Types[DataType].Low := 0;
  Types[DataType].High := ConstIndex - 1;
  end; // CompileEnumeratedType




  procedure CompileTypedPointerType(var DataType: Integer);
  var
    NestedDataType: Integer;
  begin
  // Add new anonymous type
  Inc(NumTypes);
  if NumTypes > MAXTYPES then
    Error('Maximum number of types exceeded');
    
  Types[NumTypes].Kind := POINTERTYPE;
  DataType := NumTypes;

  // Compile pointer base type
  NextTok;
  CompileTypeIdent(NestedDataType, TRUE);
    
  Types[DataType].BaseType := NestedDataType;
  Types[DataType].Block := BlockStack[BlockStackTop].Index;
  end; // CompileTypedPointerType
  
  
  
  
  procedure CompileArrayType(var DataType: Integer);
  var
    ArrType, IndexType, NestedDataType: Integer;
  begin
  NextTok;
  EatTok(OBRACKETTOK);

  DataType := NumTypes + 1;

  repeat
    // Add new anonymous type
    Inc(NumTypes);
    if NumTypes > MAXTYPES then
      Error('Maximum number of types exceeded');
    
    Types[NumTypes].Kind := ARRAYTYPE;
    Types[NumTypes].Block := BlockStack[BlockStackTop].Index;
    Types[NumTypes].IsOpenArray := FALSE;
    ArrType := NumTypes;

    CompileType(IndexType);
    if not (Types[IndexType].Kind in OrdinalTypes) then
      Error('Ordinal type expected');
    Types[ArrType].IndexType := IndexType;

    if Tok.Kind <> COMMATOK then Break;
    
    Types[ArrType].BaseType := NumTypes + 1;
    NextTok;
  until FALSE;

  EatTok(CBRACKETTOK);
  EatTok(OFTOK);

  CompileType(NestedDataType);
  Types[ArrType].BaseType := NestedDataType;  
  end; // CompileArrayType
  
  
  
  
  procedure CompileRecordType(var DataType: Integer);
  

    procedure DeclareField(const Name: TString; RecType, FieldType: Integer; var NextFieldOffset: Integer);
    var
      i: Integer;
    begin
    for i := 1 to Types[RecType].NumFields do
      if Types[RecType].Field[i]^.Name = Name then
        Error('Duplicate field ' + Name);

    // Add new field
    Inc(Types[RecType].NumFields);
    New(Types[RecType].Field[Types[RecType].NumFields]);
    
    Types[RecType].Field[Types[RecType].NumFields]^.Name     := Name;
    Types[RecType].Field[Types[RecType].NumFields]^.DataType := FieldType;
    Types[RecType].Field[Types[RecType].NumFields]^.Offset   := NextFieldOffset;
    
    NextFieldOffset := NextFieldOffset + TypeSize(FieldType);
    end; // DeclareField
    
    
    
    procedure CompileFields(RecType: Integer; var NextFieldOffset: Integer);
    var
      FieldInListName: array [1..MAXFIELDS] of TString;
      NumFieldsInList, FieldInListIndex: Integer;
      FieldType: Integer;
      
    begin
    while not (Tok.Kind in [CASETOK, ENDTOK, CPARTOK]) do
      begin
      NumFieldsInList := 0;
      
      repeat
        AssertIdent;

        Inc(NumFieldsInList);
        FieldInListName[NumFieldsInList] := Tok.Name;

        NextTok;

        if Tok.Kind <> COMMATOK then Break;
        NextTok;
      until FALSE;

      EatTok(COLONTOK);

      CompileType(FieldType);

      for FieldInListIndex := 1 to NumFieldsInList do
        DeclareField(FieldInListName[FieldInListIndex], DataType, FieldType, NextFieldOffset);

      if Tok.Kind <> SEMICOLONTOK then Break; 
      NextTok;
      end; // while
    
    end; // CompileFields
    

  
  var
    TagName: TString;
    TagVal: TConst;
    TagType, TagValType: Integer;
    NextFieldOffset, VariantStartOffset: Integer;
    
  
  begin // CompileRecordType
  NextFieldOffset := 0;
  
  // Add new anonymous type
  Inc(NumTypes);
  if NumTypes > MAXTYPES then
    Error('Maximum number of types exceeded');  
  
  Types[NumTypes].Kind := RECORDTYPE;
  Types[NumTypes].Block := BlockStack[BlockStackTop].Index;
  Types[NumTypes].NumFields := 0;
  DataType := NumTypes;

  NextTok;
  
  // Fixed fields
  CompileFields(DataType, NextFieldOffset);
  
  // Variant fields
  if Tok.Kind = CASETOK then
    begin   
    NextTok;
    
    // Tag field
    AssertIdent;
    TagName := Tok.Name;
    NextTok;
    EatTok(COLONTOK);
    
    CompileType(TagType);    
    if not (Types[TagType].Kind in OrdinalTypes) then
      Error('Ordinal type expected');
      
    DeclareField(TagName, DataType, TagType, NextFieldOffset);
    VariantStartOffset := NextFieldOffset;
    
    EatTok(OFTOK);
    
    // Variants
    repeat
      repeat
        CompileConstExpression(TagVal, TagValType);
        GetCompatibleType(TagType, TagValType);
        if Tok.Kind <> COMMATOK then Break;
        NextTok; 
      until FALSE;
  
      EatTok(COLONTOK);
      EatTok(OPARTOK);
      
      NextFieldOffset := VariantStartOffset;
      CompileFields(DataType, NextFieldOffset);
      
      EatTok(CPARTOK);      
      if Tok.Kind <> SEMICOLONTOK then Break; 
      NextTok;      
    until Tok.Kind = ENDTOK;
    
    end; // if
    
  EatTok(ENDTOK);
  end; // CompileRecordType




  procedure CompileSetType(var DataType: Integer);
  var
    NestedDataType: Integer;
  begin
  // Add new anonymous type
  Inc(NumTypes);
  if NumTypes > MAXTYPES then
    Error('Maximum number of types exceeded');
  
  Types[NumTypes].Kind := SETTYPE;
  Types[NumTypes].Block := BlockStack[BlockStackTop].Index;
  DataType := NumTypes;
  
  NextTok;
  EatTok(OFTOK);

  CompileType(NestedDataType);
  
  if (LowBound(NestedDataType) < 0) or (HighBound(NestedDataType) > MAXSETELEMENTS - 1) then
    Error('Too many set elements');
  
  Types[DataType].BaseType := NestedDataType; 
  end; // CompileSetType
  
  
  
  
  procedure CompileFileType(var DataType: Integer);
  var
    NestedDataType: Integer;
  begin
  NextTok;
  
  if Tok.Kind = OFTOK then          // Typed file
    begin
    NextTok;
    CompileType(NestedDataType);
    
    if Types[NestedDataType].Kind = FILETYPE then
      Error('Incompatible types'); 
   
    // Add new anonymous type
    Inc(NumTypes);
    if NumTypes > MAXTYPES then
      Error('Maximum number of types exceeded');
  
    Types[NumTypes].Kind := FILETYPE;
    Types[NumTypes].Block := BlockStack[BlockStackTop].Index;    
    Types[NumTypes].BaseType := NestedDataType;
    
    DataType := NumTypes;
    end
  else                              // Untyped/text file
    DataType := FILETYPEINDEX; 
 
  end; // CompileFileType
  



  procedure CompileSubrangeType(var DataType: Integer);
  var
    ConstVal: TConst;
    LowBoundType, HighBoundType: Integer;
  begin
  // Add new anonymous type
  Inc(NumTypes);
  if NumTypes > MAXTYPES then
    Error('Maximum number of types exceeded');    
  
  Types[NumTypes].Kind := SUBRANGETYPE;
  DataType := NumTypes;

  CompileConstExpression(ConstVal, LowBoundType);                               // Subrange lower bound
  if not (Types[LowBoundType].Kind in OrdinalTypes + [SUBRANGETYPE]) then
    Error('Ordinal type expected');
  Types[DataType].Low := ConstVal.Value;

  EatTok(RANGETOK);

  CompileConstExpression(ConstVal, HighBoundType);                              // Subrange upper bound
  if not (Types[HighBoundType].Kind in OrdinalTypes + [SUBRANGETYPE]) then
    Error('Ordinal type expected');
  Types[DataType].High := ConstVal.Value;

  GetCompatibleType(LowBoundType, HighBoundType);

  if Types[DataType].High < Types[DataType].Low then
    Error('Illegal subrange bounds');

  Types[DataType].BaseType := LowBoundType;
  Types[DataType].Block := BlockStack[BlockStackTop].Index;  
  end; // CompileSubrangeType
  
  
  
  
  procedure CompileProceduralType(var DataType: Integer; IsFunction: Boolean);
  begin
  Inc(NumTypes);
  if NumTypes > MAXTYPES then
    Error('Maximum number of types exceeded');    
  
  Types[NumTypes].Kind := PROCEDURALTYPE;
  Types[NumTypes].Block := BlockStack[BlockStackTop].Index;
  DataType := NumTypes;
  
  NextTok;
  
  CompileFormalParametersAndResult(IsFunction, 
                                   Types[DataType].NumParams, 
                                   Types[DataType].NumDefaultParams, 
                                   Types[DataType].Param, 
                                   Types[DataType].ResultType, 
                                   Types[DataType].IsStdCall);  
  end; // CompileProceduralType
  
  

var
  IdentIndex: LongInt;
  TypeNameGiven: Boolean;   


begin // CompileType

if Tok.Kind = PACKEDTOK then        // PACKED has no effect
  begin
  NextTok;
  if not (Tok.Kind in [ARRAYTOK, RECORDTOK, SETTOK, FILETOK]) then
    Error('PACKED is not allowed here');
  end;
 
case Tok.Kind of

  OPARTOK:
    CompileEnumeratedType(DataType);
    
  DEREFERENCETOK: 
    CompileTypedPointerType(DataType);
  
  ARRAYTOK:       
    CompileArrayType(DataType); 
 
  RECORDTOK:      
    CompileRecordType(DataType);
    
  SETTOK:      
    CompileSetType(DataType); 
   
  STRINGTOK:
    begin 
    DataType := STRINGTYPEINDEX;
    NextTok;
    end;
    
  FILETOK:
    CompileFileType(DataType);
    
  PROCEDURETOK, FUNCTIONTOK:
    CompileProceduralType(DataType, Tok.Kind = FUNCTIONTOK)
     
else                                                                              // Subrange or type name
  TypeNameGiven := FALSE;
  IdentIndex := 0;
  if Tok.Kind = IDENTTOK then      
    begin
    IdentIndex := GetIdent(Tok.Name);
    if Ident[IdentIndex].Kind = USERTYPE then TypeNameGiven := TRUE;
    end;

  if TypeNameGiven then                                                           // Type name
    begin
    DataType := Ident[IdentIndex].DataType;
    NextTok;
    end
  else                                                                            // Subrange
    CompileSubrangeType(DataType);
    
end; // case  

end;// CompileType




procedure CompileBlock(BlockIdentIndex: Integer);



  procedure ResolveForwardReferences;
  var
    TypeIndex, TypeIdentIndex, FieldIndex: Integer;
    DataType: Integer;    
  begin 
  for TypeIndex := 1 to NumTypes do
    if Types[TypeIndex].Kind = FORWARDTYPE then
      begin
      TypeIdentIndex := GetIdent(Types[TypeIndex].TypeIdentName);     
      
      if Ident[TypeIdentIndex].Kind <> USERTYPE then
        Error('Type name expected');
        
      // Forward reference resolution
      DataType := Ident[TypeIdentIndex].DataType;
      
      Types[TypeIndex] := Types[DataType];
      
      if Types[DataType].Kind = RECORDTYPE then
        for FieldIndex := 1 to Types[DataType].NumFields do
          begin
          New(Types[TypeIndex].Field[FieldIndex]);
          Types[TypeIndex].Field[FieldIndex]^ := Types[DataType].Field[FieldIndex]^;
          end;
      end; // if    
  end; // ResolveForwardReferences    



 
  procedure CompileLabelDeclarations;
  begin
  repeat
    AssertIdent;
    
    DeclareIdent(Tok.Name, GOTOLABEL, 0, 0, VALPASSING, 0, 0.0, EMPTYPROC);
    
    NextTok;
    if Tok.Kind <> COMMATOK then Break;
    NextTok;
  until FALSE;
  
  EatTok(SEMICOLONTOK);
  end; // CompileLabelDeclarations


 
  
  procedure CompileConstDeclarations;
  
  
  
    procedure CompileUntypedConstDeclaration(var NameTok: TToken);
    var
      ConstVal: TConst;
      ConstValType: Integer;    
    begin
    EatTok(EQTOK);
    
    CompileConstExpression(ConstVal, ConstValType);
    DeclareIdent(NameTok.Name, CONSTANT, 0, ConstValType, VALPASSING, ConstVal.Value, ConstVal.FracValue, EMPTYPROC);
    end; // CompileUntypedConstDeclaration;
    
    
    
    
    procedure CompileTypedConstDeclaration(var NameTok: TToken);
    
    
      procedure CompileTypedConstConstructor(InitializedDataOffset: LongInt; ConstType: Integer);
      const
        TrueVal: Boolean = True;
      
      var
        ConstVal, ElementVal, ElementVal2: TConst;
        ConstValType, ElementValType: Integer;
        NumElements, ElementIndex, FieldIndex: Integer;
        
      begin
      // Numbers
      if Types[ConstType].Kind in OrdinalTypes + [REALTYPE] then
        begin
        CompileConstExpression(ConstVal, ConstValType);          
        GetCompatibleType(ConstType, ConstValType); 
          
        if Types[ConstType].Kind = REALTYPE then
          Move(ConstVal.FracValue, InitializedGlobalData[InitializedDataOffset], TypeSize(ConstType))
        else
          Move(ConstVal.Value, InitializedGlobalData[InitializedDataOffset], TypeSize(ConstType));
        end
        
      // Arrays
      else if Types[ConstType].Kind = ARRAYTYPE then
        begin
        
        if ConstType = STRINGTYPEINDEX then         // Special case: strings
          begin
          if (Tok.Kind <> CHARLITERALTOK) and (Tok.Kind <> STRINGLITERALTOK) then
            CheckTok(STRINGLITERALTOK);
            
          Move(InitializedGlobalData[Tok.StrAddress], InitializedGlobalData[InitializedDataOffset], TypeSize(ConstType));
          NextTok;
          end
        else                                        // General rule
          begin
          EatTok(OPARTOK);
          
          NumElements := HighBound(Types[ConstType].IndexType) - LowBound(Types[ConstType].IndexType) + 1;
          for ElementIndex := 1 to NumElements do
            begin
            CompileTypedConstConstructor(InitializedDataOffset, Types[ConstType].BaseType);
            InitializedDataOffset := InitializedDataOffset + TypeSize(Types[ConstType].BaseType);
            
            if ElementIndex < NumElements then 
              EatTok(COMMATOK)
            else
              EatTok(CPARTOK);  
            end; // for
          end; // else
 
        end
        
      // Records
      else if Types[ConstType].Kind = RECORDTYPE then
        begin
        EatTok(OPARTOK);
        
        repeat
          AssertIdent;
          FieldIndex := GetField(ConstType, Tok.Name);
          
          NextTok;
          EatTok(COLONTOK);
          
          CompileTypedConstConstructor(InitializedDataOffset + Types[ConstType].Field[FieldIndex]^.Offset, Types[ConstType].Field[FieldIndex]^.DataType);          
          
          if Tok.Kind <> SEMICOLONTOK then Break;
          NextTok; 
        until FALSE;
        
        EatTok(CPARTOK);
        end
        
      // Sets
      else if Types[ConstType].Kind = SETTYPE then
        begin
        EatTok(OBRACKETTOK);
        
        if Tok.Kind <> CBRACKETTOK then
          repeat      
            CompileConstExpression(ElementVal, ElementValType);            
            GetCompatibleType(ElementValType, Types[ConstType].BaseType);

            if Tok.Kind = RANGETOK then
              begin
              NextTok;
              CompileConstExpression(ElementVal2, ElementValType);    
              GetCompatibleType(ElementValType, Types[ConstType].BaseType);
              end
            else
              ElementVal2 := ElementVal;
              
            for ElementIndex := ElementVal.Value to ElementVal2.Value do
              Move(TrueVal, InitializedGlobalData[InitializedDataOffset + ElementIndex], TypeSize(BOOLEANTYPEINDEX));
  
            if Tok.Kind <> COMMATOK then Break;
            NextTok;
          until FALSE;
        
        EatTok(CBRACKETTOK);
        end        
     
      else
        Error('Illegal type');         
 
      end; // CompileTypedConstConstructor  
    
    
    var
      ConstType: Integer;
      
      
    begin // CompileTypedConstDeclaration
    EatTok(COLONTOK);    
    CompileType(ConstType);
    
    DeclareIdent(NameTok.Name, CONSTANT, 0, ConstType, VARPASSING, 0, 0.0, EMPTYPROC);
    
    EatTok(EQTOK);    
    CompileTypedConstConstructor(Ident[NumIdent].Value, ConstType);   
    end; // CompileTypedConstDeclaration    



  
  var
    NameTok: TToken; 
   
  begin // CompileConstDeclarations
  repeat
    AssertIdent;

    NameTok := Tok;
    NextTok;
    
    if Tok.Kind = EQTOK then
      CompileUntypedConstDeclaration(NameTok)
    else
      CompileTypedConstDeclaration(NameTok);

    EatTok(SEMICOLONTOK);
  until Tok.Kind <> IDENTTOK;
  end; // CompileConstDeclarations
  
  

  
  procedure CompileTypeDeclarations;
  var
    NameTok: TToken;
    VarType: Integer;
  begin
  repeat
    AssertIdent;

    NameTok := Tok;
    NextTok;
    EatTok(EQTOK);

    CompileType(VarType);
    DeclareIdent(NameTok.Name, USERTYPE, 0, VarType, VALPASSING, 0, 0.0, EMPTYPROC);   
    
    EatTok(SEMICOLONTOK);
  until Tok.Kind <> IDENTTOK;

  ResolveForwardReferences;
  end; // CompileTypeDeclarations
  
  
  
  
  procedure CompileVarDeclarations;
  var
    IdentInListName: array [1..MAXPARAMS] of TString;
    NumIdentInList, IdentInListIndex: Integer;
    VarType: Integer;
  begin
  repeat
    NumIdentInList := 0;
    repeat
      AssertIdent;

      Inc(NumIdentInList);
      IdentInListName[NumIdentInList] := Tok.Name;

      NextTok;

      if Tok.Kind <> COMMATOK then Break;
      NextTok;
    until FALSE;

    EatTok(COLONTOK);

    CompileType(VarType);

    for IdentInListIndex := 1 to NumIdentInList do
      DeclareIdent(IdentInListName[IdentInListIndex], VARIABLE, 0, VarType, VALPASSING, 0, 0.0, EMPTYPROC);

    EatTok(SEMICOLONTOK);
  until Tok.Kind <> IDENTTOK;

  ResolveForwardReferences;
  end; // CompileVarDeclarations




  procedure CompileProcFuncDeclarations(IsFunction: Boolean);

    
    function CompileDirective: Boolean;
    var
      ImportLibName, ImportFuncName: TString;
      
    begin
    Result := FALSE;
    
    if Tok.Kind = IDENTTOK then
      if Tok.Name = 'EXTERNAL' then      // External (Windows API) declaration  
        begin
        if BlockStackTop <> 1 then
          Error('External declaration must be global');
          
        // Read import library name
        NextTok;      
        ImportLibName := Tok.Name;
        EatTok(STRINGLITERALTOK);      
        
        // Read import function name
        if (Tok.Kind <> IDENTTOK) or (Tok.Name <> 'NAME') then
          Error('NAME expected but ' + GetTokSpelling(Tok.Kind) + ' found');
        NextTok;
        ImportFuncName := Tok.Name;
        EatTok(STRINGLITERALTOK);

        // Register import function
        GenerateImportFuncStub(AddImportFunc(ImportLibName, ImportFuncName));
        
        EatTok(SEMICOLONTOK);
        Result := TRUE;
        end
      else if Tok.Name = 'FORWARD' then  // Forward declaration
        begin
        Inc(NumBlocks);
        if NumBlocks > MAXBLOCKS then
          Error('Maximum number of blocks exceeded');
          
        Ident[NumIdent].ProcAsBlock := NumBlocks;
        Ident[NumIdent].IsUnresolvedForward := TRUE;
        GenerateForwardReference;
        
        NextTok;
        EatTok(SEMICOLONTOK);
        Result := TRUE;
        end
      else
        Error('Unknown directive ' + Tok.Name);  
    end; // CompileDirective
    
    


    function CompileInterface: Boolean;
    begin
    Result := FALSE;
    
    // Procedure interface in the interface section of a unit is an implicit forward declaration
    if IsInterfaceSection and (BlockStack[BlockStackTop].Index = 1) then
      begin 
      Inc(NumBlocks);
      if NumBlocks > MAXBLOCKS then
        Error('Maximum number of blocks exceeded');
        
      Ident[NumIdent].ProcAsBlock := NumBlocks;
      Ident[NumIdent].IsUnresolvedForward := TRUE;
      GenerateForwardReference;

      Result := TRUE;
      end;
      
    end; // CompileInterface

    
  
  var
    ForwardIdentIndex: Integer;

    
  begin // CompileProcFuncDeclarations   
  AssertIdent;

  // Check for forward declaration resolution
  ForwardIdentIndex := GetIdentUnsafe(Tok.Name);
  if ForwardIdentIndex <> 0 then
    if not Ident[ForwardIdentIndex].IsUnresolvedForward or
       (Ident[ForwardIdentIndex].Block <> BlockStack[BlockStackTop].Index) or
       ((Ident[ForwardIdentIndex].Kind <> PROC) and not IsFunction) or
       ((Ident[ForwardIdentIndex].Kind <> FUNC) and IsFunction) then
     ForwardIdentIndex := 0;                                      // Found an identifier of another kind or scope, or it is already resolved

  if ForwardIdentIndex = 0 then
    begin
    
    if IsFunction then
      DeclareIdent(Tok.Name, FUNC, 0, 0, VALPASSING, 0, 0.0, EMPTYPROC)
    else
      DeclareIdent(Tok.Name, PROC, 0, 0, VALPASSING, 0, 0.0, EMPTYPROC);

    NextTok;

    CompileFormalParametersAndResult(IsFunction, 
                                     Ident[NumIdent].NumParams, 
                                     Ident[NumIdent].NumDefaultParams, 
                                     Ident[NumIdent].Param, 
                                     Ident[NumIdent].DataType, 
                                     Ident[NumIdent].IsStdCall);
    end// if ForwardIdentIndex = 0
  else
    NextTok;
    

  EatTok(SEMICOLONTOK);
  
  
  // Procedure/function body, if any
  if ForwardIdentIndex <> 0 then                                      // Forward declaration resolution
    begin   
    GenerateForwardResolution(Ident[ForwardIdentIndex].Value);
    
    CompileBlock(ForwardIdentIndex);
    EatTok(SEMICOLONTOK); 
    
    Ident[ForwardIdentIndex].IsUnresolvedForward := FALSE; 
    end  
  else if not CompileDirective and not CompileInterface then          // Declaration in the interface part, external or forward declaration                                                              
    begin
    Inc(NumBlocks);                                                   // Conventional declaration
    if NumTypes > MAXBLOCKS then
      Error('Maximum number of blocks exceeded');
    
    Ident[NumIdent].ProcAsBlock := NumBlocks;
    
    CompileBlock(NumIdent);    
    EatTok(SEMICOLONTOK);
    end;                                                               
   
  end; // CompileProcFuncDeclarations
  



  procedure CompileDeclarations;
  var
    DeclTok: TToken;
    ParamIndex, StackParamIndex: Integer;
    TotalNumParams: Integer;
    NestedProcsFound: Boolean;
   
  begin  
  NestedProcsFound := FALSE; 
 
  // For procedures and functions, declare parameters and the Result variable
  if BlockStack[BlockStackTop].Index <> 1 then             
    begin
    // Declare parameters like local variables
    TotalNumParams := Ident[BlockIdentIndex].NumParams;
    if (Ident[BlockIdentIndex].Kind = FUNC) and (Types[Ident[BlockIdentIndex].DataType].Kind in StructuredTypes) then
      Inc(TotalNumParams);                          // Allocate space for structured Result as a hidden VAR parameter
    
    for ParamIndex := 1 to Ident[BlockIdentIndex].NumParams do
      begin
      if Ident[BlockIdentIndex].IsStdCall then
        StackParamIndex := Ident[BlockIdentIndex].NumParams - ParamIndex + 1    // Inverse parameter stack for STDCALL procedures (structured Result is not allowed anyway)
      else
        StackParamIndex := ParamIndex;
  
      DeclareIdent(Ident[BlockIdentIndex].Param[StackParamIndex]^.Name,
                   VARIABLE,
                   TotalNumParams,
                   Ident[BlockIdentIndex].Param[StackParamIndex]^.DataType,
                   Ident[BlockIdentIndex].Param[StackParamIndex]^.PassMethod,
                   0,
                   0.0,
                   EMPTYPROC);
      end;             

    // Allocate Result variable if the current block is a function
    if Ident[BlockIdentIndex].Kind = FUNC then
      begin
      if Types[Ident[BlockIdentIndex].DataType].Kind in StructuredTypes then    // For functions returning structured variables, Result is a hidden VAR parameter 
        DeclareIdent('RESULT', VARIABLE, TotalNumParams, Ident[BlockIdentIndex].DataType, VARPASSING, 0, 0.0, EMPTYPROC)
      else                                                                      // Otherwise, Result is a hidden local variable
        DeclareIdent('RESULT', VARIABLE, 0, Ident[BlockIdentIndex].DataType, VALPASSING, 0, 0.0, EMPTYPROC);
        
      Ident[BlockIdentIndex].ResultIdentIndex := NumIdent;
      end;  
    end; // if

  
  // Loop over interface/implementation sections
  repeat
  
    // Local declarations
    while Tok.Kind in [LABELTOK, CONSTTOK, TYPETOK, VARTOK, PROCEDURETOK, FUNCTIONTOK] do
      begin
      DeclTok := Tok;
      NextTok;
      
      case DeclTok.Kind of
        LABELTOK:
          CompileLabelDeclarations;
          
        CONSTTOK:     
          CompileConstDeclarations;
          
        TYPETOK:      
          CompileTypeDeclarations;
          
        VARTOK:       
          CompileVarDeclarations;
          
        PROCEDURETOK, FUNCTIONTOK:
          begin
          if (BlockStack[BlockStackTop].Index <> 1) and not NestedProcsFound then
            begin
            NestedProcsFound := TRUE;
            GenerateNestedProcsProlog;
            end;
    
          CompileProcFuncDeclarations(DeclTok.Kind = FUNCTIONTOK);
          end;
      end; // case

      end;// while
      
      
    if IsUnit and IsInterfaceSection and (BlockStack[BlockStackTop].Index = 1) then
      begin
      EatTok(IMPLEMENTATIONTOK);
      IsInterfaceSection := FALSE;
      end
    else
      Break;    
    
  until FALSE;      

    
  // Jump to entry point
  if NestedProcsFound then
    GenerateNestedProcsEpilog;
    
  end; // CompileDeclarations
  
  
  
  
  procedure CheckUnresolvedDeclarations;
  var
    IdentIndex: Integer;
  begin
  IdentIndex := NumIdent;
  
  while (IdentIndex > 0) and (Ident[IdentIndex].Block = BlockStack[BlockStackTop].Index) do
    begin
    if (Ident[IdentIndex].Kind in [GOTOLABEL, PROC, FUNC]) and Ident[IdentIndex].IsUnresolvedForward then
      Error('Unresolved declaration of ' + Ident[IdentIndex].Name);
    Dec(IdentIndex);
    end;
  end; // CheckUnresolvedDeclarations  
  
  


  procedure DeleteDeclarations;
  var
    ParamIndex, FieldIndex: Integer;
    
  begin  
  // Delete local identifiers to save space
  while (NumIdent > 0) and (Ident[NumIdent].Block = BlockStack[BlockStackTop].Index) do
    begin 
    // If procedure or function, delete parameters first
    if Ident[NumIdent].Kind in [PROC, FUNC] then
      for ParamIndex := 1 to Ident[NumIdent].NumParams do
        Dispose(Ident[NumIdent].Param[ParamIndex]);

    // Delete identifier itself
    Dec(NumIdent);
    end;     
    
  // Delete local types
  while (NumTypes > 0) and (Types[NumTypes].Block = BlockStack[BlockStackTop].Index) do
    begin
    // If procedural type, delete parameters first
    if Types[NumTypes].Kind = PROCEDURALTYPE then
      for ParamIndex := 1 to Types[NumTypes].NumParams do
        Dispose(Types[NumTypes].Param[ParamIndex]); 
    
    // If record, delete fields first
    if Types[NumTypes].Kind = RECORDTYPE then
      for FieldIndex := 1 to Types[NumTypes].NumFields do
        Dispose(Types[NumTypes].Field[FieldIndex]);

    // Delete type itself
    Dec(NumTypes);
    end;
      
  end; // DeleteDeclarations




var
  LibProcIdentIndex: Integer;
  TotalNumParams: Integer;


begin // CompileBlock
Inc(BlockStackTop);

with BlockStack[BlockStackTop] do
  begin
  if BlockIdentIndex = 0 then Index := 1 else Index := Ident[BlockIdentIndex].ProcAsBlock;    
  LocalDataSize := 0;
  ParamDataSize := 0; 
  TempDataSize := 0;
  end;
  
if (NumUnits = 1) and (BlockStack[BlockStackTop].Index = 1) then
  begin
  DeclarePredefinedTypes;
  DeclarePredefinedIdents;
  end; 
  
CompileDeclarations;

if IsUnit and (BlockStack[BlockStackTop].Index = 1) then
  begin
  // Main block of a unit (may contain the implementation part, but not statements) 
    
  CheckUnresolvedDeclarations;    
  EatTok(ENDTOK);  
  end
else
  begin
  // Main block of a program, or a procedure as part of a program/unit  
  
  if BlockStack[BlockStackTop].Index = 1 then
    SetProgramEntryPoint;

  GenerateStackFrameProlog;

  if BlockStack[BlockStackTop].Index = 1 then          // Main program
    begin
    GenerateFPUInit;
    
    // Initialize heap and console I/O
    LibProcIdentIndex := GetIdent('INITSYSTEM');
    GenerateCall(Ident[LibProcIdentIndex].Value, BlockStackTop - 1, Ident[LibProcIdentIndex].NestingLevel);  
    end;


  // Block body
  GenerateGotoProlog;
  GenerateExitProlog;

  CompileCompoundStatement(0);

  CheckUnresolvedDeclarations;

  GenerateExitEpilog;                            // Direct all Exit procedure calls here
  GenerateGotoEpilog;

  if ForLoopNesting <> 0 then
    Error('Internal fault: Illegal FOR loop nesting');

  // If function, return Result value via the EAX register
  if (BlockStack[BlockStackTop].Index <> 1) and (Ident[BlockIdentIndex].Kind = FUNC) then
    begin
    PushVarPtr(Ident[Ident[BlockIdentIndex].ResultIdentIndex].Value, LOCAL, 0, UNINITDATARELOC);
    if Types[Ident[BlockIdentIndex].DataType].Kind in StructuredTypes then
      DerefPtr(POINTERTYPEINDEX)
    else  
      DerefPtr(Ident[BlockIdentIndex].DataType);
    SaveStackTopToEAX;
    end;

  if BlockStack[BlockStackTop].Index = 1 then          // Main program
    begin
    LibProcIdentIndex := GetIdent('EXITPROCESS');  
    PushConst(0);
    InverseStack(Ident[LibProcIdentIndex].NumParams);
    GenerateCall(Ident[LibProcIdentIndex].Value, 1, 1);
    end;

  GenerateStackFrameEpilog(BlockStack[BlockStackTop].LocalDataSize + BlockStack[BlockStackTop].TempDataSize);

  if BlockStack[BlockStackTop].Index <> 1 then         
    begin
    TotalNumParams := Ident[BlockIdentIndex].NumParams;
    if (Ident[BlockIdentIndex].Kind = FUNC) and (Types[Ident[BlockIdentIndex].DataType].Kind in StructuredTypes) then
      Inc(TotalNumParams);                            // Deallocate space allocated for structured Result as a hidden VAR parameter
      
    GenerateReturn(TotalNumParams * SizeOf(LongInt), Ident[BlockIdentIndex].NestingLevel);
    
    DeleteDeclarations;
    end;

  end; // else    
  
Dec(BlockStackTop);
end;// CompileBlock




procedure CompileUsesClause;
var
  UnitIndex: Integer;
begin
NextTok;  

repeat 
  AssertIdent;
  UnitIndex := GetUnit(Tok.Name);
  Units[UnitIndex].IsUsed := TRUE;
  
  NextTok;
  
  if Tok.Kind <> COMMATOK then Break;
  NextTok;
until FALSE;

EatTok(SEMICOLONTOK);  
   
end; // CompileUsesClause  




procedure CompileProgramOrUnit;
var
  UnitIndex: Integer;
  
begin
Inc(NumUnits);
if NumUnits > MAXUNITS then
  Error('Maximum number of units exceeded');

NextTok;

IsUnit := FALSE;
if Tok.Kind = UNITTOK then
  IsUnit := TRUE
else
  CheckTok(PROGRAMTOK);
  
NextTok; 
AssertIdent;
Units[NumUnits].Name := Tok.Name;

NextTok;
EatTok(SEMICOLONTOK);

IsInterfaceSection := FALSE;
if IsUnit then
  begin
  EatTok(INTERFACETOK);
  IsInterfaceSection := TRUE;
  end;
  
for UnitIndex := 1 to NumUnits do
  Units[UnitIndex].IsUsed := FALSE;
  
// Always use System unit, except when compiling System unit itself
if NumUnits > 1 then
  Units[1].IsUsed := TRUE; 

if Tok.Kind = USESTOK then
  CompileUsesClause;   

NumBlocks := 1;  
CompileBlock(0);

CheckTok(PERIODTOK);
end;// CompileProgram


end.

