@stack = global [1000 x i8*] undef ; stack containing pointer to i8 
@sp = global i64 undef ; global stack pointer
@true = global [2 x i8] c"1\00"
@false = global [2 x i8] c"0\00"

declare i64 @atol(i8*)
declare i64 @strtol(i8*, i8** )
declare i64 @snprintf(i8*, ...)
declare i64 @printf(i8*, ...)
declare void @llvm.memcpy.p0i8.p0i8.i64(i8* nocapture, i8* nocapture readonly,
                                                                  i64, i32, i1)

@to_str  = private unnamed_addr constant [3 x i8] c"%i\00"
@pushing = private unnamed_addr constant [12 x i8] c"Pushing %s\0A\00"
@popped  = private unnamed_addr constant [11 x i8] c"Popped %s\0A\00"

@before_casting  = private unnamed_addr constant [17 x i8] c"Before casting \0A\00"
@after_casting  = private unnamed_addr constant [18 x i8] c"After casting %i\0A\00"

define void @push(i8* %str_ptr) {
  ; dereferencing @sp by loading value into memory
  %sp   = load i64* @sp

  ; get position on the stack, the stack pointer points to. this is the top of
  ; the stack.
  ; nice getelementptr FAQ: http://llvm.org/docs/GetElementPtr.html
  ;                     value of pointer type,  index,    field
  %top = getelementptr [1000 x i8*]* @stack,   i8 0,     i64 %sp

  ; the contents of memory are updated to contain %str_ptr at the location
  ; specified by the %addr operand
  store i8* %str_ptr, i8** %top

  ; increase stack pointer to point to new free, top of stack
  %newsp = add i64 %sp, 1
  store i64 %newsp, i64* @sp
  
  ret void
}

; pops element from stack and converts in integer
; returns the element, in case of error undefined
define i64 @pop_int(){
  ; pop
  %top = call i8* @pop()

  ; convert to int, check for error
  %top_int = call i64 @atol(i8* %top)
 
  ; return
  ret i64 %top_int
}

define void @push_int(i64 %top_int)
{  
  ; allocate memory to store string in
  %buffer = alloca [2 x i8]  
  %buffer_addr = getelementptr [2 x i8]* %buffer, i8 0, i64 0
  %to_str_ptr = getelementptr [3 x i8]* @to_str, i64 0, i64 0

  ; convert to string
  ;FIXME currently at most 1000 bytes are copied via snprintf 
  call i64(i8*, ...)* @snprintf(
          i8* %buffer_addr, i64 1000, i8* %to_str_ptr, i64 %top_int)
  
  ; push on stack 
  call void(i8*)* @push(i8* %buffer_addr)

  ret void
}

define void @add_int() {
  ; get top of stack
  %top_1   = call i64()* @pop_int()

  ; get second top of stack
  %top_2   = call i64()* @pop_int()

  ; add the two values
  %res = add i64 %top_1, %top_2

  ; store result on stack
  call void(i64)* @push_int(i64 %res)

  ret void
}

define void @sub_int() {
  ; get top of stack
  %top_1   = call i64()* @pop_int()

  ; get second top of stack
  %top_2   = call i64()* @pop_int()

  ; sub the two values
  %res = sub i64 %top_1, %top_2

  ; store result on stack
  call void(i64)* @push_int(i64 %res)

  ret void
}
@number0 = private unnamed_addr constant [2 x i8] c"5\00"
@number1  = private unnamed_addr constant [2 x i8] c"2\00"

define i32 @main() {
 ; push two numbers on the stack
 %number0 = getelementptr [2 x i8]* @number0, i64 0, i64 0   
 %number1 = getelementptr [2 x i8]* @number1, i64 0, i64 0   

 %t = call i64 @get_numeric_type(i8* %number0)
 %after_casting_ptr = getelementptr [18 x i8]* @after_casting, i64 0, i64 0
 call i64(i8*, ...)* @printf(i8* %after_casting_ptr,i64 %t)

 %pushingptr = getelementptr [12 x i8]* @pushing, i64 0, i64 0
 call i64(i8*, ...)* @printf(i8* %pushingptr, i8* %number0)
 call void(i8*)* @push(i8* %number0)

 call i64(i8*, ...)* @printf(i8* %pushingptr, i8* %number1)
 call void(i8*)* @push(i8* %number1)

 call void @sub_int() 

 %poppedptr = getelementptr [11 x i8]* @popped, i64 0, i64 0
 %sum  = call i8*()* @pop()
 call i64(i8*, ...)* @printf(i8* %poppedptr, i8* %sum)


 ret i32 0
}

define i8* @peek() {
  %sp   = load i64* @sp
  %top_of_stack = sub i64 %sp, 1
  %addr = getelementptr [1000 x i8*]* @stack, i8 0, i64 %top_of_stack
  %val = load i8** %addr
  ret i8* %val
}

define i8* @pop() {
  %val = call i8*()* @peek()
  %sp = load i64* @sp
  %top_of_stack = sub i64 %sp, 1
  store i64 %top_of_stack, i64* @sp
  ret i8* %val
}

; UNTESTED
define i64 @strlen(i8* %str) {
entry:
  br label %loop
loop:
  %i = phi i64 [1, %entry ], [ %next_i, %loop ]
  %next_i = add i64 %i, 1
  %addr = getelementptr i8* %str, i64 %i
  %c = load i8* %addr
  %cond = icmp eq i8 %c, 0
  br i1 %cond, label %finished, label %loop
finished:
  ret i64 %i
}

; UNTESTED
define i8* @streq(i8* %str1, i8* %str2) {
entry:
  br label %loop
loop:
  ; the phi instruction says that coming from the 'entry' label i is 1
  ; otherwise (coming from 'cont') i will be 'next_i'
  %i = phi i64 [ 1, %entry ], [ %next_i, %cont ]

  ; the the actual character
  %addr1 = getelementptr i8* %str1, i64 %i
  %addr2 = getelementptr i8* %str2, i64 %i
  %c1 = load i8* %addr1
  %c2 = load i8* %addr2

  ; compare character
  %cond = icmp eq i8 %c1, %c2 

  ; if equal, jump to next character otherwise jump to 'fail' 
  br i1 %cond, label %cont, label %fail

cont:
  %next_i = add i64 %i, 1
  %cond2 = icmp eq i8 %c1, 0 
  br i1 %cond2, label %success, label %loop
success:
  %t = getelementptr [2 x i8]* @true, i64 0, i64 0
  ret i8* %t
fail:	
  %f = getelementptr [2 x i8]* @true, i64 0, i64 0
  ret i8* %f
}

; checks whether a given string is a float or an integer
; returns 0 if string is neither integer nor float
; returns 1 if string is an integer
; returns 2 if string is an float
define i64 @get_numeric_type(i8* %szNumbers) #0 {
  %1 = alloca i8*, align 8
  %pEnd = alloca i8*, align 8
  %li1 = alloca i64, align 8
  store i8* %szNumbers, i8** %1, align 8
  %2 = load i8** %1, align 8
  %3 = call i64 @strtol(i8* %2, i8** %pEnd) #2
  store i64 %3, i64* %li1, align 8
  %4 = load i64* %li1, align 8
  ret i64 %4
}

