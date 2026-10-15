// Chaves das traduções. Os textos estão em assets/translations/<língua>.json
// (pt, en, es, fr); usa-os com `context.tr(Keys.x)` nos widgets ou `tr(Keys.x)`
// fora deles (ver core/i18n/translations.dart).
//
// Chaves com plural (marcadas abaixo) têm no JSON as variantes "<chave>.one" e
// "<chave>.other": usa-as com `context.trPlural(Keys.x, n)`.
//
// Ao acrescentar uma chave, acrescenta-a também aos quatro JSON: o teste
// test/translations_test.dart falha se faltar alguma.

/// Chaves de tradução.
abstract final class Keys {
  // Comum -----------------------------------------------------------------
  static const commonCancel = 'common.cancel';
  static const commonDelete = 'common.delete';
  static const commonAccept = 'common.accept';
  static const commonDecline = 'common.decline';
  static const commonRemove = 'common.remove';
  static const commonGallery = 'common.gallery';
  static const commonCamera = 'common.camera';
  static const commonPhotosPermission = 'common.photosPermission';
  static const commonToday = 'common.today';
  static const commonYesterday = 'common.yesterday';
  static const commonYesterdayAt = 'common.yesterdayAt';
  static const commonDateAt = 'common.dateAt';

  /// Plural (`.one` / `.other`).
  static const commonPeople = 'common.people';

  // Definições ------------------------------------------------------------
  static const settingsLanguage = 'settings.language';
  static const settingsLanguageSystem = 'settings.language.system';

  // Nomes das línguas (iguais em todas) -----------------------------------
  static const languagePt = 'language.pt';
  static const languageEn = 'language.en';
  static const languageEs = 'language.es';
  static const languageFr = 'language.fr';

  // Conversas -------------------------------------------------------------
  static const chatTab = 'chat.tab';
  static const chatFriendsTooltip = 'chat.friendsTooltip';
  static const chatFilterAll = 'chat.filter.all';
  static const chatFilterGifts = 'chat.filter.gifts';
  static const chatFilterDirect = 'chat.filter.direct';
  static const chatFilterUnread = 'chat.filter.unread';

  /// Plural (`.one` / `.other`).
  static const chatFriendRequests = 'chat.friendRequests';
  static const chatEmptyTitle = 'chat.empty.title';
  static const chatEmptyMessage = 'chat.empty.message';
  static const chatEmptyMessageLocal = 'chat.empty.messageLocal';
  static const chatEmptyCreateGroup = 'chat.empty.createGroup';
  static const chatEmptyHaveCode = 'chat.empty.haveCode';
  static const chatEmptyAddFriends = 'chat.empty.addFriends';
  static const chatFilterEmptyUnread = 'chat.filterEmpty.unread';
  static const chatFilterEmptyDirect = 'chat.filterEmpty.direct';
  static const chatFilterEmptyGifts = 'chat.filterEmpty.gifts';
  static const chatSayHello = 'chat.sayHello';
  static const chatPreviewYou = 'chat.previewYou';
  static const chatPreviewSender = 'chat.previewSender';
  static const chatGroupTalkHere = 'chat.group.talkHere';
  static const chatGiftPurchased = 'chat.gift.purchased';

  /// Plural (`.one` / `.other`).
  static const chatGiftAwaiting = 'chat.gift.awaiting';
  static const chatGiftYouBuy = 'chat.gift.youBuy';
  static const chatGiftCollected = 'chat.gift.collected';
  static const chatGiftPay = 'chat.gift.pay';
  static const chatGiftPaid = 'chat.gift.paid';
  static const chatGiftToConfirm = 'chat.gift.toConfirm';
  static const chatGiftForName = 'chat.gift.forName';
  static const chatGiftForNameDate = 'chat.gift.forNameDate';
  static const chatNewTitle = 'chat.new.title';
  static const chatNewGroup = 'chat.new.group';
  static const chatNewGroupHint = 'chat.new.groupHint';
  static const chatNewDirect = 'chat.new.direct';
  static const chatNewCode = 'chat.new.code';
  static const chatNewNeedFriend = 'chat.new.needFriend';
  static const chatNewPickFriend = 'chat.new.pickFriend';
  static const chatTypingSelf = 'chat.typingSelf';
  static const chatTypingOne = 'chat.typingOne';
  static const chatTypingTwo = 'chat.typingTwo';
  static const chatTypingMany = 'chat.typingMany';
  static const chatOnline = 'chat.online';
  static const chatOnlineCount = 'chat.onlineCount';
  static const chatLastSeenToday = 'chat.lastSeen.today';
  static const chatLastSeenYesterday = 'chat.lastSeen.yesterday';
  static const chatLastSeenDate = 'chat.lastSeen.date';
  static const chatSeen = 'chat.seen';
  static const chatSeenByOne = 'chat.seenByOne';
  static const chatSeenByTwo = 'chat.seenByTwo';
  static const chatSeenByMany = 'chat.seenByMany';
  static const chatSeenByEveryone = 'chat.seenByEveryone';
  static const chatSeenSheetTitle = 'chat.seenSheet.title';
  static const chatSeenSheetNobody = 'chat.seenSheet.nobody';
  static const chatHeaderDirect = 'chat.header.direct';
  static const chatHeaderGroup = 'chat.header.group';
  static const chatHeaderGiftFor = 'chat.header.giftFor';
  static const chatHeaderMembers = 'chat.header.members';
  static const chatHeaderMembersMore = 'chat.header.membersMore';
  static const chatHeaderSeeGift = 'chat.header.seeGift';
  static const chatBlocked = 'chat.blocked';
  static const chatEmptyGroupTitle = 'chat.emptyGroup.title';
  static const chatEmptyGroupMessage = 'chat.emptyGroup.message';
  static const chatEmptyGroupMessageFor = 'chat.emptyGroup.messageFor';
  static const chatEmptyDirectMessage = 'chat.emptyDirect.message';
  static const chatBannerPurchased = 'chat.banner.purchased';
  static const chatBannerProgress = 'chat.banner.progress';
  static const chatBannerFor = 'chat.banner.for';
  static const chatActionMoreEmoji = 'chat.action.moreEmoji';
  static const chatActionReply = 'chat.action.reply';
  static const chatActionCopy = 'chat.action.copy';
  static const chatActionSaveSticker = 'chat.action.saveSticker';
  static const chatActionWhoSaw = 'chat.action.whoSaw';
  static const chatActionRetry = 'chat.action.retry';
  static const chatActionDiscard = 'chat.action.discard';
  static const chatActionDeleteForAll = 'chat.action.deleteForAll';
  static const chatCopied = 'chat.copied';
  static const chatStickerSaved = 'chat.stickerSaved';
  static const chatDeleteTitle = 'chat.delete.title';
  static const chatDeleteMessage = 'chat.delete.message';
  static const chatDeletedAccount = 'chat.deletedAccount';
  static const chatNotSent = 'chat.notSent';
  static const chatMessage = 'chat.message';
  static const chatDeleted = 'chat.deleted';
  static const chatPreviewPhoto = 'chat.preview.photo';
  static const chatPreviewPhotoCaption = 'chat.preview.photoCaption';
  static const chatPreviewGif = 'chat.preview.gif';
  static const chatPreviewSticker = 'chat.preview.sticker';
  static const chatComposerReplyingTo = 'chat.composer.replyingTo';
  static const chatComposerCancelReply = 'chat.composer.cancelReply';
  static const chatComposerSendPhoto = 'chat.composer.sendPhoto';
  static const chatComposerEmoji = 'chat.composer.emoji';
  static const chatComposerSend = 'chat.composer.send';
  static const chatComposerGifsStickers = 'chat.composer.gifsStickers';
  static const chatMediaEmoji = 'chat.media.emoji';
  static const chatMediaGifs = 'chat.media.gifs';
  static const chatMediaStickers = 'chat.media.stickers';
  static const chatMediaNoRecents = 'chat.media.noRecents';
  static const chatMediaSearchEmoji = 'chat.media.searchEmoji';
  static const chatMediaSearchStickers = 'chat.media.searchStickers';
  static const chatMediaSearchGifs = 'chat.media.searchGifs';
  static const chatMediaStickerCreated = 'chat.media.stickerCreated';
  static const chatMediaDeleteStickerTitle = 'chat.media.deleteSticker.title';
  static const chatMediaDeleteStickerMessage = 'chat.media.deleteSticker.message';
  static const chatMediaMine = 'chat.media.mine';
  static const chatMediaSearch = 'chat.media.search';
  static const chatMediaCreate = 'chat.media.create';
  static const chatMediaStickersHint = 'chat.media.stickersHint';
  static const chatGroupCardTitle = 'chat.groupCard.title';
  static const chatGroupCardEmpty = 'chat.groupCard.empty';

  // Convites para grupos --------------------------------------------------
  static const inviteFriends = 'invite.friends';
  static const inviteInvited = 'invite.invited';
  static const inviteInvite = 'invite.invite';
  static const inviteOrSearch = 'invite.orSearch';

  // Amigos ----------------------------------------------------------------
  static const friendsTitle = 'friends.title';
  static const friendsAddTitle = 'friends.add.title';
  static const friendsAddHint = 'friends.add.hint';
  static const friendsAddAction = 'friends.add.action';
  static const friendsIncoming = 'friends.incoming';
  static const friendsList = 'friends.list';
  static const friendsListCount = 'friends.listCount';
  static const friendsEmpty = 'friends.empty';
  static const friendsChat = 'friends.chat';
  static const friendsChatWith = 'friends.chatWith';
  static const friendsRemoveAction = 'friends.removeAction';
  static const friendsRemoveTitle = 'friends.remove.title';
  static const friendsRemoveMessage = 'friends.remove.message';
  static const friendsOutgoing = 'friends.outgoing';
  static const friendsWaiting = 'friends.waiting';
  static const friendsRequestCancelled = 'friends.requestCancelled';
  static const friendsResultSent = 'friends.result.sent';
  static const friendsResultAccepted = 'friends.result.accepted';
  static const friendsResultAlreadyFriends = 'friends.result.alreadyFriends';
  static const friendsResultAlreadySent = 'friends.result.alreadySent';
  static const friendsResultSelf = 'friends.result.self';
  static const friendsResultNotFound = 'friends.result.notFound';

  // Perfil de outra pessoa (aberto no chat) -------------------------------
  static const profileSheetYou = 'profileSheet.you';
  static const profileSheetFriends = 'profileSheet.friends';
  static const profileSheetSendMessage = 'profileSheet.sendMessage';
  static const profileSheetWantsFriend = 'profileSheet.wantsFriend';
  static const profileSheetRequestSent = 'profileSheet.requestSent';
  static const profileSheetCancelRequest = 'profileSheet.cancelRequest';
  static const profileSheetAddFriend = 'profileSheet.addFriend';

  // Erros -----------------------------------------------------------------
  static const errorFriendRequestGone = 'error.friendRequestGone';
  static const errorDirectOnlyFriends = 'error.directOnlyFriends';
  static const errorNotFriendsAnymore = 'error.notFriendsAnymore';
  static const errorTooManyStickers = 'error.tooManyStickers';
  static const errorGifsUnavailable = 'error.gifsUnavailable';
}
