module Main
  ( setUp
  , manageTrigger
  , notify
  , notifyAtFOTM
  ) where

import Prelude

import Data.Argonaut.Core (fromObject, fromString, stringify)
import Data.Array (length)
import Data.Int (toNumber)
import Data.JSDate (JSDate, getDate, getDay, getFullYear, getMonth, jsdateLocal, now)
import Data.Maybe (fromJust, isJust, isNothing)
import Data.Options ((:=))
import Data.Tuple (Tuple(..), fst, snd)
import Effect (Effect, foreachE)
import Effect.Exception (throw)
import Foreign.Object (fromHomogeneous)
import GAS.CalendarApp (getCalendarById)
import GAS.CalendarApp.Calendar (getEventsForDay)
import GAS.PropertiesService (getScriptProperties)
import GAS.PropertiesService.Properties (Properties, getProperty)
import GAS.ScriptApp (deleteTrigger, getProjectTriggers, newTrigger)
import GAS.ScriptApp.ClockTriggerBuilder (at, atHour, create, everyDays)
import GAS.ScriptApp.Trigger (getHandlerFunction)
import GAS.ScriptApp.TriggerBuilder (timeBased)
import GAS.UrlFetchApp (Method(..), contentType, fetchWithParams, method, payload)
import Partial.Unsafe (unsafePartial)
import Type.Data.Boolean (kind Boolean)

todayEff :: Effect JSDate
todayEff = do
  today <- now
  year <- getFullYear today
  month <- getMonth today
  day <- getDate today
  jsdateLocal { year
              , month
              , day
              , hour: 0.0
              , minute: 0.0
              , second: 0.0
              , millisecond: 0.0
              }

isHolidayEff :: JSDate -> Effect Boolean
isHolidayEff date = do
  calendar <- getCalendarById "ja.japanese#holiday@group.v.calendar.google.com"
  events <- getEventsForDay date calendar
  pure $ length events > 0

isWednesdayEff :: JSDate -> Effect Boolean
isWednesdayEff date = do
  d <- getDay date
  pure $ d == 3.0

plus1Day :: JSDate -> Effect JSDate
plus1Day date = do
  year <- getFullYear date
  month <- getMonth date
  day <- getDate date
  jsdateLocal { year
              , month
              , day: day + 1.0
              , hour: 0.0
              , minute: 0.0
              , second: 0.0
              , millisecond: 0.0
              }

getFirstBusinessDate :: Effect JSDate
getFirstBusinessDate = do
  today <- todayEff
  year <- getFullYear today
  month <- getMonth today
  loop $ jsdateLocal { year
                     , month
                     , day: 1.0
                     , hour: 0.0
                     , minute: 0.0
                     , second: 0.0
                     , millisecond: 0.0
                     }
  where
    loop :: Effect JSDate -> Effect JSDate
    loop date = do
      d <- date
      isWednesday <- isWednesdayEff d
      isHoliday <- isHolidayEff d
      case Tuple isWednesday isHoliday of
        Tuple true false -> date
        _ -> loop $ plus1Day d

everyDayTriggerHour :: Int
everyDayTriggerHour = 2

notificationTimes :: Array (Tuple Int Int)
notificationTimes = [ Tuple 8 50
                    , Tuple 12 50
                    ]

createEveryDayTrigger :: String -> Int -> Effect Unit
createEveryDayTrigger name hour =
  void $ newTrigger name >>= timeBased
                         >>= atHour hour
                         >>= everyDays 1
                         >>= create

createAtTimeTriggers :: String -> Array (Tuple Int Int) -> Effect Unit
createAtTimeTriggers name times = do
  today <- todayEff
  foreachE times \time -> do
    year <- getFullYear today
    month <- getMonth today
    day <- getDate today
    notificationTime <- jsdateLocal { year
                                    , month
                                    , day
                                    , hour: toNumber <<< fst $ time
                                    , minute: toNumber <<< snd $ time
                                    , second: 0.0
                                    , millisecond: 0.0
                                    }
    void $ newTrigger name >>= timeBased
                           >>= at notificationTime
                           >>= create

deleteTriggers :: String -> Effect Unit
deleteTriggers name = do
  triggers <- getProjectTriggers
  foreachE triggers \t -> do
    h <- getHandlerFunction t
    when (h == name) do
      deleteTrigger t

setUp :: Effect Unit
setUp = do
  let handler = "manageTrigger"
  deleteTriggers handler
  createEveryDayTrigger handler everyDayTriggerHour

manageTrigger :: Effect Unit
manageTrigger = do
  let weeklyHandler = "notify"
  let firstOfTheMonthHandler = "notifyAtFOTM"
  deleteTriggers weeklyHandler
  deleteTriggers firstOfTheMonthHandler
  today <- todayEff
  isWednesday <- isWednesdayEff today
  isHoliday <- isHolidayEff today
  firstBusinessDate <- getFirstBusinessDate
  when (isWednesday && not isHoliday) do
    createAtTimeTriggers weeklyHandler notificationTimes
    when (today == firstBusinessDate) do
      createAtTimeTriggers firstOfTheMonthHandler $ map (\t -> Tuple (fst t) ((+) 1 <<< snd $ t)) notificationTimes

getOrThrowIdobataHookUrl :: Properties -> Effect String
getOrThrowIdobataHookUrl props = do
  maybeIdobataHookUrl <- getProperty "idobataHookUrl" props
  when (isNothing maybeIdobataHookUrl) do
    throw "idobataHookUrl property is required"
  pure $ unsafePartial $ fromJust maybeIdobataHookUrl

getOrThrowMessage :: Properties -> Effect String
getOrThrowMessage props = do
  maybeMessage <- getProperty "message" props
  when (isNothing maybeMessage) do
    throw "message property is required"
  pure $ unsafePartial $ fromJust maybeMessage

notify :: Effect Unit
notify = do
  scriptProps <- getScriptProperties
  idobataHookUrl <- getOrThrowIdobataHookUrl scriptProps
  message <- getOrThrowMessage scriptProps
  postIdobata idobataHookUrl message

notifyAtFOTM :: Effect Unit
notifyAtFOTM = do
  scriptProps <- getScriptProperties
  idobataHookUrl <- getOrThrowIdobataHookUrl scriptProps
  maybeFirstOfTheMonthMessage <- getProperty "firstOfTheMonthMessage" scriptProps
  when (isJust maybeFirstOfTheMonthMessage) do
    let firstOfTheMonthMessage = unsafePartial $ fromJust maybeFirstOfTheMonthMessage
    postIdobata idobataHookUrl firstOfTheMonthMessage

postIdobata :: String -> String -> Effect Unit
postIdobata url message = do
  let json = stringify <<< fromObject <<< fromHomogeneous $ { source: fromString message }
  void $ fetchWithParams url $
    method := POST <>
    contentType := "application/json" <>
    payload := json
