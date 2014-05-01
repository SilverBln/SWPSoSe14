﻿module Preprocessor (
                     process   -- main function of the module "Preprocessor"
					)
 where
 
 -- imports --
 import InterfaceDT as IDT
 
 -- functions --
 process :: IDT.Input2PreProc -> IDT.PreProc2Lexer
 process (IIP input) = (IPL output)
  where
   output = (removeLines . groupFunctionsToGrid2D) input   
    where
	-- remove strings from list until first string begins with a dollar-sign
    removeLines :: Grid2D -> Grid2D
    removeLines []                   = []
    removeLines []:lines             = removeLines lines
    removeLines line:lines
                | (head line == '$') = line:lines
                | otherwise          = removeLines lines

    -- put every function/program into its on grid such that the dollar sign is the first character in the first line
    groupFunctionsToGrid2Ds :: Grid2D -> [Grid2D]
    groupFunctionsToGrid2Ds grid = helperGF grid [] []
     where
      helperGFtG2D [] akk1 akk2        = akk2
      helperGFtG2D (zeile:rest) akk1 akk2
                   | head zeile == '$' = helperGFtG2D rest [zeile] (akk2 ++ [akk1])
                   | otherwise         = helperGFtG2D rest (akk1++[zeile]) akk2