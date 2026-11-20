module Main (main) where

import BoardSpec qualified
import ContactSpec qualified
import FileSpec qualified
import HeaderSpec qualified
import LimitSpec qualified
import LoginSpec qualified
import OpenApiSpec qualified
import PdfSpec qualified
import SessionSpec qualified
import StudyApiSpec qualified
import StudyStoreSpec qualified
import Test.Hspec
import TileSpec qualified
import WebSpec qualified

main :: IO ()
main = hspec $ do
  HeaderSpec.spec
  LimitSpec.spec
  FileSpec.spec
  TileSpec.spec
  ContactSpec.spec
  SessionSpec.spec
  LoginSpec.spec
  StudyStoreSpec.spec
  StudyApiSpec.spec
  PdfSpec.spec
  BoardSpec.spec
  OpenApiSpec.spec
  WebSpec.spec
