{-# LANGUAGE TupleSections, OverloadedStrings, MultiWayIf #-}
module Handler.Thread where
 
import           Import
import           Yesod.Auth
import           Prelude            (head)
import qualified Data.Text          as T
import qualified Database.Esqueleto as E
import qualified Data.Map.Strict    as Map
import           Utils.YobaMarkup        (doYobaMarkup)
import           Handler.Captcha    (checkCaptcha, recordCaptcha, getCaptchaInfo, updateAdaptiveCaptcha)
import           Handler.Posting

import           Text.Blaze.Html.Renderer.String
-------------------------------------------------------------------------------------------------------------------
-- Костыли-костылики...
getJsonFromMsgR :: Text -> Handler TypedContent
getJsonFromMsgR status = do
  msg <- getMessage
  selectRep $
    provideJson $ object [(status, toJSON $ renderHtml $ fromJust msg)]
-------------------------------------------------------------------------------------------------------------------
getThreadR :: Text -> Int -> Handler Html
getThreadR board thread = do
  when (thread == 0) notFound
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  checkViewAccess mgroup boardVal
  let permissions      = getPermissions mgroup
      hasAccessToReply = checkAccessToReply mgroup boardVal
      maxMessageLength = boardMaxMsgLength    boardVal
      enableCaptcha    = boardEnableCaptcha   boardVal
      opModeration     = boardOpModeration    boardVal
      boardDesc        = boardTitle     boardVal
      boardLongDesc    = boardSummary boardVal
      geoIpEnabled     = boardEnableGeoIp     boardVal
  -------------------------------------------------------------------------------------------------------
  allPosts' <- runDB $ E.select $ E.from $ \(post `E.LeftOuterJoin` file) -> do
    E.on $ (E.just (post E.^. PostId)) E.==. (file E.?. AttachedfileParentId)
    E.where_ ((post E.^. PostBoard       ) E.==. (E.val board ) E.&&.
              (post E.^. PostDeletedByOp ) E.==. (E.val False ) E.&&.
              (post E.^. PostDeleted     ) E.==. (E.val False ) E.&&.
             ((post E.^. PostParent      ) E.==. (E.val thread) E.||.
             ((post E.^. PostParent      ) E.==. (E.val 0     ) E.&&. (post E.^. PostLocalId) E.==. (E.val thread))))
    E.orderBy [E.asc (post E.^. PostId)]
    return (post, file)
  when (null allPosts') notFound
  let allPosts        = map (second catMaybes) $ Map.toList $ keyValuesToMap allPosts'
      repliesAndFiles = drop 1 allPosts
      eOpPost         = fst $ head allPosts
      opPostFiles     = snd $ head allPosts
      pt              = postTitle  $ entityVal eOpPost
      pm              = stripTags $ unTextarea $ postMessage $ entityVal eOpPost
      pagetitle | not $ T.null pt                                 = pt
                | not $ T.null $ T.filter (`notElem`" \r\n\t") pm = if T.length pm > 60 then flip T.append "…" $ T.take 60 pm else pm
                | otherwise                                     = ""
  -------------------------------------------------------------------------------------------------------
  geoIps    <- getCountries (if geoIpEnabled then allPosts else [])
  -------------------------------------------------------------------------------------------------------
  acaptcha  <- lookupSession "acaptcha"
  when (isNothing acaptcha && enableCaptcha && isNothing muser) $ recordCaptcha =<< getConfig configCaptchaLength
  ------------------------------------------------------------------------------------------------------- 
  (formWidget, formEnctype) <- generateFormPost $ postForm boardVal
  (formWidget', _)          <- generateFormPost editForm
  nameOfTheBoard   <- extraSiteName <$> getExtra
  maybeCaptchaInfo <- getCaptchaInfo
  msgrender        <- getMessageRender
  timeZone        <- getTimeZone

  noDeletedPosts   <- (==0) <$> runDB (count [PostBoard ==. board, PostParent ==. thread, PostDeletedByOp ==. True])
  defaultLayout $ do
    setUltDestCurrent
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " — ", boardDesc, if T.null pagetitle then "" else " — ", pagetitle]
    $(widgetFile "thread")
-------------------------------------------------------------------------------------------------------------------
postThreadR :: Text -> Int -> Handler Html
postThreadR board thread = do
  when (thread == 0) notFound
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  checkViewAccess mgroup boardVal

  maybeParent <- runDB $ selectFirst [PostBoard ==. board, PostLocalId ==. thread] []
  -------------------------------------------------------------------------------------------------------     
  let defaultName      = boardDefaultName   boardVal
      allowedTypes     = boardAllowedTypes  boardVal
      thumbSize        = boardThumbSize     boardVal
      bumpLimit        = boardBumpLimit     boardVal
      enableCaptcha    = boardEnableCaptcha boardVal
      replyFile        = boardReplyFile     boardVal
      threadUrl        = ThreadR board thread
  -------------------------------------------------------------------------------------------------------         
  ((result, _), _) <- runFormPost $ postForm boardVal
  case result of
    FormFailure []                     -> trickyRedirect "error" MsgBadFormData threadUrl
    FormFailure xs                     -> trickyRedirect "error" (MsgError $ T.intercalate "; " xs) threadUrl
    FormMissing                        -> trickyRedirect "error" MsgNoFormData  threadUrl
    FormSuccess (name, title, message, pswd, captcha, files, goback, Just nobump)
      | replyFile == "Disabled"&& not (noFiles files)         -> trickyRedirect "error" MsgReplyFileIsDisabled threadUrl
      | replyFile == "Required"&& noFiles files             -> trickyRedirect "error" MsgNoFile              threadUrl
      | (\(Just (Entity _ p)) -> postLocked p) maybeParent -> trickyRedirect "error" MsgLockedThread        threadUrl
      | noMessage message && noFiles files                 -> trickyRedirect "error" MsgNoFileOrText        threadUrl
      | not $ all (isFileAllowed allowedTypes) files        -> trickyRedirect "error" MsgTypeNotAllowed      threadUrl
      | otherwise                                         -> do
        -- save form values in case something goes wrong
        setSession "message"    (maybe     "" unTextarea message)
        setSession "post-title" (fromMaybe "" title)
        ip        <- pack <$> getIp
        -- check ban
        ban <- runDB $ selectFirst [BanIp ==. ip] [Desc BanId]
        when (isJust ban) $
          unlessM (isBanExpired $ fromJust ban) $ do
            let m =  MsgYouAreBanned (banReason $ entityVal $ fromJust ban)
                                     (maybe "never" (pack . myFormatTime 0) (banExpires $ entityVal $ fromJust ban))
            trickyRedirect "error" m threadUrl
        -- check captcha
        when (enableCaptcha && isNothing muser) $ do
          acaptcha  <- lookupSession "acaptcha"
          when (isNothing acaptcha) $ do
            void $ when (isNothing captcha) (trickyRedirect "error" MsgWrongCaptcha threadUrl)
            checkCaptcha (fromJust captcha) (trickyRedirect "error" MsgWrongCaptcha threadUrl)
          updateAdaptiveCaptcha acaptcha
        ------------------------------------------------------------------------------------------------------           
        now      <- liftIO getCurrentTime
        -- check too fast posting
        lastPost <- runDB $ selectFirst [PostIp ==. ip, PostParent !=. 0] [Desc PostDate] -- last reply by IP
        when (isJust lastPost) $ do
          let diff = ceiling ((realToFrac $ diffUTCTime now (postDate $ entityVal $ fromJust lastPost)) :: Double)
          whenM ((>diff) <$> getConfig configReplyDelay) $ 
            deleteSession "acaptcha" >>
            trickyRedirect "error" MsgPostingTooFast threadUrl
        ------------------------------------------------------------------------------------------------------
        posterId         <- getPosterId
        messageFormatted <- doYobaMarkup message board thread
        lastPost'        <- runDB (selectFirst [PostBoard ==. board] [Desc PostLocalId])
        when (isNothing lastPost') $  -- reply to non-existent thread
          trickyRedirect "error" MsgNoSuchThread (BoardNoPageR board)
        let nextId  = 1 + postLocalId (entityVal $ fromJust lastPost')
            newPost = Post { postBoard        = board
                           , postLocalId      = nextId
                           , postParent       = thread
                           , postMessage      = messageFormatted
                           , postRawMessage   = maybe "" unTextarea message
                           , postTitle        = maybe ("" :: Text) (T.take 60) title
                           , postName         = maybe defaultName (T.take 20) name
                           , postDate         = now
                           , postPassword     = pswd
                           , postBumped       = Nothing
                           , postIp           = ip
                           , postLocked       = False
                           , postSticked      = False
                           , postAutosage     = False
                           , postDeleted      = False
                           , postDeletedByOp  = False
                           , postOwner        = (pack . show . userGroup . entityVal) <$> muser
                           , postPosterId     = posterId
                           , postLastModified = Nothing                                                
                           }
        void $ insertFiles files thumbSize =<< runDB (insert newPost)
        -------------------------------------------------------------------------------------------------------
        -- bump thread if it's necessary
        isBumpLimit <- (\x -> x >= bumpLimit && bumpLimit > 0) <$> runDB (count [PostParent ==. thread])
        unless (nobump || isBumpLimit || postAutosage (entityVal $ fromJust maybeParent)) $ bumpThread board thread now
        -- remember poster name
        when (isJust name) $ setSession "name" (fromMaybe defaultName name)
        -- everything went well, delete these values
        deleteSession "message"
        deleteSession "post-title"
        case goback of
          ToBoard  -> setSession "goback" "ToBoard"  >> trickyRedirect "ok" MsgPostSent (BoardNoPageR board)
          ToThread -> setSession "goback" "ToThread" >> trickyRedirect "ok" MsgPostSent threadUrl
    _  -> trickyRedirect "error" MsgUnknownError threadUrl
