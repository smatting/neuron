{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.Zettelkasten.Query.Parser where

import Control.Monad.Except
import Data.Some
import Data.TagTree (mkTagPattern)
import Neuron.Zettelkasten.Connection
import Neuron.Zettelkasten.ID
import Neuron.Zettelkasten.Query
import Neuron.Zettelkasten.Query.Error
import Neuron.Zettelkasten.Query.Theme
import Relude
import Text.MMark.MarkdownLink (MarkdownLink (..))
import qualified Text.URI as URI
import Text.URI.QQ (queryKey)
import Text.URI.Util (getQueryParam, hasQueryFlag)

-- | Parse a query from the given URI.
--
-- This function is used only in the CLI. For handling links in a Markdown file,
-- your want `queryFromMarkdownLink` which allows specifying the link text as
-- well.
queryFromURI :: MonadError QueryParseError m => URI.URI -> m (Maybe (Some Query))
queryFromURI uri = do
  -- We are setting markdownLinkText to the URI to support the new short links
  queryFromMarkdownLink $ MarkdownLink {markdownLinkUri = uri, markdownLinkText = URI.render uri}

queryFromMarkdownLink :: MonadError QueryParseError m => MarkdownLink -> m (Maybe (Some Query))
queryFromMarkdownLink MarkdownLink {markdownLinkUri = uri, markdownLinkText = linkText} =
  case fmap URI.unRText (URI.uriScheme uri) of
    Just proto | not angleBracketLink && proto `elem` ["z", "zcf"] -> do
      zid <- liftEither $ first (QueryParseError_InvalidID uri) $ parseZettelID' linkText
      let mconn = if proto == "zcf" then Just OrdinaryConnection else Nothing
      pure $ Just $ Some $ Query_ZettelByID zid mconn
    Just proto | proto `elem` ["zquery", "zcfquery"] ->
      case uriHost uri of
        Right "search" -> do
          let mconn = if proto == "zcfquery" then Just OrdinaryConnection else Nothing
          pure $ Just $ Some $
            Query_ZettelsByTag (tagPatterns "tag") mconn queryView
        Right "tags" ->
          pure $ Just $ Some $ Query_Tags (tagPatterns "filter")
        _ ->
          throwError $ QueryParseError_UnsupportedHost uri
    _ -> pure $ do
      -- Initial support for the upcoming short links.
      -- First, we expect that this is inside <..> (so same link text as link)
      guard angleBracketLink
      -- Then, non-relevant parts of the URI should be empty
      guard
        `mapM_` [ URI.uriAuthority uri == Left False,
                  URI.uriFragment uri == Nothing
                ]
      let mconn =
            if hasQueryFlag [queryKey|cf|] uri
              then Just OrdinaryConnection
              else Nothing
      case fmap URI.unRText (URI.uriScheme uri) of
        Just "z" -> do
          fmap snd (URI.uriPath uri) >>= \case
            (URI.unRText -> "zettels") :| [] -> do
              pure $ Some $ Query_ZettelsByTag (tagPatterns "tag") mconn queryView
            (URI.unRText -> "tags") :| [] -> do
              pure $ Some $ Query_Tags (tagPatterns "filter")
            _ ->
              Nothing
        Just _ -> do
          Nothing
        Nothing -> do
          -- Alias to short links
          fmap snd (URI.uriPath uri) >>= \case
            (URI.unRText -> path) :| [] -> do
              zid <- rightToMaybe $ parseZettelID' path
              pure $ Some $ Query_ZettelByID zid mconn
            _ ->
              -- Multiple path elements, not supported
              Nothing
  where
    angleBracketLink = URI.render uri == linkText
    tagPatterns k =
      mkTagPattern <$> getParamValues k uri
    queryView =
      let isTimeline =
            -- linkTheme=withDate is legacy format; timeline is current standard.
            getQueryParam [queryKey|linkTheme|] uri == Just "withDate"
              || hasQueryFlag [queryKey|timeline|] uri
          isGrouped = hasQueryFlag [queryKey|grouped|] uri
       in ZettelsView (LinkView isTimeline) isGrouped
    getParamValues k u =
      flip mapMaybe (URI.uriQuery u) $ \case
        URI.QueryParam (URI.unRText -> key) (URI.unRText -> val) ->
          if key == k
            then Just val
            else Nothing
        _ -> Nothing
    uriHost u =
      fmap (URI.unRText . URI.authHost) (URI.uriAuthority u)
