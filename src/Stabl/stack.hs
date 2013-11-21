import Data.Char (isDigit)
import Data.List (words, any, all)

import Parser

underflow = "stack underflow!"

pop [] = error underflow
pop (x:xs) = xs

-- See - Forth
dup [] = error underflow
dup (x:xs) = x:x:xs

-- See - Forth
-- NOTE: implement generalization of this word?
over [] = error underflow
over [x] = error underflow
over (x:y:xs) = (y:x:y:xs)

-- See - Forth
-- TODO: implement instead with more general word?
swap [] = error underflow
swap [_] = error underflow
swap (x:y:xs) = y:x:xs

tokenize :: String -> [String]
tokenize = words

-- TODO: update type to be 

-- | interpret a program given by a String
interpret :: String -> Int
interpret s = interpret' (program,[]) 
  where program = case parseStabl "" s
                  of Right pro -> pro
                     -- Left ParseError -> error "parse error!" 


interpret' :: ([Stabl],[Stabl]) -> Int
interpret' ([],stack) = case (head stack) of Lit num -> num; WordCall w -> error "type error!"
interpret' (Lit n : xs, stack) = interpret' (xs, Lit n : stack)
interpret' (WordCall s : xs, stack) = 
    let (¤) = case s of -- TODO: really hardcoded
            "add"   -> (+)
            "minus" -> (-)
            "mul"   -> (*)
            "div"   -> div 
            other   -> error $ "invalid word: " ++ other 
                            in interpret' (xs, eval stack (¤))
                                                       
 -- TODO: refactor this method into a more general one: one which takes an arbitary binary operator, a stack, and uses the two operands at the top of the stack to evaluate it (or throws stack underflow if there aren't at least two elements on the stack.)

eval :: [Stabl] -> (Int -> Int -> Int) -> [Stabl]
eval stack (¤) = let x = head stack
                     y = head $ pop stack
                     res = (get x) ¤ (get y) 
                       where get t = case t of 
                               WordCall s -> error $ "was String, expected num: " ++ s 
                               Lit n -> n
                 in (Lit res):(pop $ pop stack)
         




 
                                                
  