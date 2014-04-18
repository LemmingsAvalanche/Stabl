module Interpreter
       (
         parseCheckAndInterpret
       , interpret
       , apply
       , CanErr
       , Dict
       ) where
import Control.Applicative
import Control.Monad
import Control.Monad.Error
import qualified Data.Map as Map

import Parser
import Text.ParserCombinators.Parsec.Error

data StablErr = StackUnderflow String
                | Parser ParseError
                | TypeMismatchErr { 
                    expected :: String
                  , actual :: String }
                | UndefinedWord String
                | Default String

instance Error StablErr where
  noMsg = Default "An error has occured"
  strMsg = Default

instance Show StablErr where
  show (StackUnderflow str) = "Stack underflow: the combinator " ++ 
                              str ++ " was called on the stack, but there were not enough elements on the stack."
  show (Parser err) = show err
  show (TypeMismatchErr exp act) = "Typemismatch error: expected " ++ exp ++ ", but got " ++ act
  show (UndefinedWord str) = "Undefined word error: tried to call word " ++ str ++ ", but it is not defined."
  show (Default str) = str

type CanErr = Either StablErr

type Dict = Map.Map String [Stabl]

top :: [Stabl] -> CanErr Stabl
top [] = Left $ StackUnderflow "top"
top (x:_) = Right x

pop :: [Stabl] -> CanErr [Stabl]
pop [] = Left $ StackUnderflow "pop"
pop (x:xs) = Right xs

-- | See - Forth
dup :: [Stabl] -> CanErr [Stabl]
dup [] = Left $ StackUnderflow "dup"
dup (x:xs) = Right $ x:x:xs

-- | See - Forth
swap :: [Stabl] -> CanErr [Stabl]
swap [] = Left $ StackUnderflow "swap"
swap [_] = Left $ StackUnderflow "swap"
swap (x:y:xs) = Right $ y:x:xs

-- | See - Forth 
rot :: [Stabl] -> CanErr [Stabl]
rot [] = Left $ StackUnderflow "rot"
rot [_] = Left $ StackUnderflow "rot"
rot [_,_] = Left $ StackUnderflow "rot"
rot (x:y:z:xs) = Right $ z:x:y:xs

-- | See - Forth
over :: [Stabl] -> CanErr [Stabl]
over [] = Left $ StackUnderflow "over"
over [_] = Left $ StackUnderflow "over"
over (x:y:xs) = Right $ y:x:y:xs

apply :: [Stabl] -> Dict -> [Stabl] -> CanErr ([Stabl], Dict)
apply stack dict quot = interpret (reverse quot ++ stack) dict
 
-- TODO: fix to make total
parseCheckAndInterpret :: String -> Dict -> CanErr ([Stabl], Dict)
parseCheckAndInterpret s dict = either
                                (Left . Parser)
                                (\prog -> interpret prog dict) 
                                (parseStabl "" s)

-- | interpret a program given by a quotation.
interpret :: [Stabl] -> Dict -> CanErr ([Stabl], Dict)
interpret s dict = interpret' (s, dict , [])

-- idé: refaktor til å bruke monad transformer? - EitherT State, noko sånt som det
interpret' :: ([Stabl], Dict, [Stabl]) -> CanErr ([Stabl], Dict)
interpret' ([], dict, []) = Right ([], dict) 
interpret' ([], dict, stack) = case (head stack) of
  LitInt num    -> Right (stack, dict)
  Quotation quot' -> Right (stack, dict)
  WordCall w -> Left $ TypeMismatchErr {
    expected = "a stack with only values"
    , actual = "an unevaluated word" }
interpret' (LitInt n : xs, dict, stack) = interpret' (xs, dict, LitInt n : stack)
interpret' (Quotation quot : xs, dict, stack) = interpret' (xs, dict, Quotation quot : stack)
interpret' (WordCall s : xs, dict, stack) =
            -- word definition
  case s of "def" ->
              case stack of Quotation [WordCall call] : Quotation body : rest -> interpret' (xs, Map.insert call body dict, rest)
                            rest -> Left TypeMismatchErr {
                              expected = "a quotation with a single word (name of word) and a quotation (the 'body' of the word)",
                              actual = "the rest of the stack: " ++ show stack} 
            -- built-in words
            -- OBS: fortsatt bug her? eller fiksa eg alt som var gale her?
            "add"   -> ifSuccessArithmetic xs stack dict (+)
            "minus" -> ifSuccessArithmetic xs stack dict (-)
            "mul"   -> ifSuccessArithmetic xs stack dict (*)
            "div"   -> ifSuccessArithmetic xs stack dict div 
              
            -- built-in stack combinators 
            "pop"   -> ifSuccessComb xs dict stack pop 
            "dup"   -> ifSuccessComb xs dict stack dup 
            "swap"  -> ifSuccessComb xs dict stack swap 
            "rot"   -> ifSuccessComb xs dict stack rot
            "over"  -> ifSuccessComb xs dict stack over 
            
            -- applying a quotation 
            -- OBS: all kode under dette bør kanskje refaktorerast
            "apply"   -> case head' of Quotation quot -> apply quot dict tail' >>= \(res', dict') -> interpret' (xs, dict', res')
                                       other -> Left $ TypeMismatchErr {
                                         expected = "a quotation"
                                         , actual = "the word: " ++ show other}
              where head' = head stack
                    tail' = tail stack
            -- user-defined word                        
            other   -> case lookup' of Just wordBody -> apply wordBody dict stack >>= \(ret', dict') -> interpret' (xs, dict', ret')
                                       Nothing       -> Left $ UndefinedWord other
              where lookup' = Map.lookup other dict

-- TODO: move to where-clase in interpret'?

ifSuccessArithmetic :: [Stabl] -> [Stabl] -> Dict -> (Integer -> Integer -> Integer) -> CanErr ([Stabl], Dict)
ifSuccessArithmetic stack retStack dict op = eval retStack op
                                             >>= 
                                             resApplyInterpret' (stack, dict)

ifSuccessComb :: [Stabl] -> Dict -> [Stabl] -> ([Stabl] -> CanErr [Stabl]) -> CanErr ([Stabl], Dict)
ifSuccessComb stack dict retStack comb = comb retStack
                                         >>= 
                                         resApplyInterpret' (stack,dict)

resApplyInterpret' :: ([Stabl], Dict) -> [Stabl] -> CanErr ([Stabl], Dict)
resApplyInterpret' (stack, dict) res = interpret' (stack, dict, res)                                         

eval :: [Stabl] -> (Integer -> Integer -> Integer) -> CanErr [Stabl]
eval stack op = let x = top stack
                    y = pop stack >>= top
                    res = liftA2 op (get y) (get x)
                       where get = (>>=
                                   (\res -> case res of 
                                                   WordCall s -> Left $ TypeMismatchErr { expected = "an int", actual = "the word: " ++ s }
                                                   LitInt n -> Right n)
                                   )
                 in res >>= (\result -> return $ (LitInt result):stack'') 
  where stack'' = (tail . tail) stack -- Uses partial functions, BUT, this is safe since the evaluation can't have come this far if there indeed weren't at least two items on top of the stack, since then we would not have been able to use arithmetic on the top two elements of the stack. 




 
                                                
  
