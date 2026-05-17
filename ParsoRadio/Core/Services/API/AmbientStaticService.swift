import Foundation

/// Returns hardcoded Track arrays for Ambient channels that don't use network services.
/// Yellowstone: 114 NPS public-domain nature sounds (AWS S3/CloudFront, no auth).
/// Loop channels: single CC0 track each from Freesound CDN (Flowing Water, Rainy Day, Ocean Waves).
final class AmbientStaticService {

    func fetchTracks(channel: Channel) -> [Track] {
        switch channel.id {
        case "ambient-yellowstone":    return yellowstoneTracks
        // Loop-authored CC0 sources (user-selected) to avoid the seam click.
        case "ambient-flowing-water":  return [loopTrack("443869", "443/443869_2155630-hq.mp3",
                                                          title: "Flowing Water", artist: "eardeer",
                                                          channelId: "ambient-flowing-water")]
        case "ambient-rain":           return [loopTrack("136971", "136/136971_2289019-hq.mp3",
                                                          title: "Rainy Day", artist: "DWOBoyle",
                                                          channelId: "ambient-rain")]
        case "ambient-ocean":          return [loopTrack("156598", "156/156598_981371-hq.mp3",
                                                          title: "Ocean Waves", artist: "Rmutt",
                                                          channelId: "ambient-ocean")]
        default: return []
        }
    }

    // MARK: - Track builders

    private func npsTrack(_ file: String, title: String) -> Track {
        let stem = file.replacingOccurrences(of: ".mp3", with: "")
        return Track(
            id: "nps-\(stem)",
            source: "nps",
            title: title,
            artist: "National Park Service",
            duration: 0,
            streamURL: URL(string: "https://www.nps.gov/nps-audiovideo/legacy/mp3/imr/avElement/\(file)")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .publicDomain,
            tags: ["yellowstone"],
            qualityScore: 1.0,
            rawCreator: "",
            composer: nil,
            instruments: [],
            metadataConfidence: 2.0
        )
    }

    private func loopTrack(_ id: String, _ cdnPath: String, title: String, artist: String, channelId: String) -> Track {
        Track(
            id: "freesound-\(id)",
            source: "freesound",
            title: title,
            artist: artist,
            duration: 0,
            streamURL: URL(string: "https://cdn.freesound.org/previews/\(cdnPath)")!,
            downloadURL: nil,
            localFilePath: nil,
            license: .cc0,
            tags: [channelId],
            qualityScore: 1.0,
            rawCreator: artist,
            composer: nil,
            instruments: [],
            metadataConfidence: 2.0
        )
    }

    // MARK: - Yellowstone (114 tracks, NPS public domain)

    private var yellowstoneTracks: [Track] {[
        // Birds
        npsTrack("yell-YELLAMCO20160914T10ms.mp3",       title: "American Coots"),
        npsTrack("yell-DipperandGeeseFireholeRiver.mp3",  title: "Dipper and Geese, Firehole River"),
        npsTrack("yell-YELLAMRO20160506SM3.mp3",          title: "American Robin"),
        npsTrack("yell-YELLBBMA20160625094526SM3.mp3",    title: "Black-Billed Magpie"),
        npsTrack("yell-YELLCAGE20160914T04ms.mp3",        title: "Canada Goose"),
        npsTrack("yell-YELLCOLO20160913T18ms.mp3",        title: "Common Loon"),
        npsTrack("yell-YELLCOYE20160712T08.mp3",          title: "Common Yellowthroat"),
        npsTrack("yell-RavenBlackSandBasin.mp3",          title: "Common Raven, Black Sand Basin"),
        npsTrack("yell-030404GeyserHillAnemoneKilldeerChorus02M10013.mp3", title: "Killdeer Chorus"),
        npsTrack("yell-YELLLAZB20160625SM303143.mp3",     title: "Lazuli Bunting"),
        npsTrack("yell-YELLMOBL20150617T26.mp3",          title: "Mountain Bluebird"),
        npsTrack("yell-YELLredwingedblackbird20150427.mp3", title: "Red-Winged Blackbird"),
        npsTrack("yell-RuffedGrouse.mp3",                 title: "Ruffed Grouse"),
        npsTrack("yell-YELLFLBCSACR20075171.mp3",         title: "Sandhill Crane"),
        npsTrack("yell-YELLSavannahSparrow20150617T22.mp3", title: "Savannah Sparrow"),
        npsTrack("yell-YELLTSOL20160506SM3.mp3",          title: "Townsend's Solitaire"),
        npsTrack("yell-YELLWarblingVireoMammoth20150614T29ms.mp3", title: "Warbling Vireo, Mammoth"),
        npsTrack("yell-YELLWEME20150425ms.mp3",           title: "Western Meadow Lark"),
        npsTrack("yell-Snipe.mp3",                        title: "Wilson's Snipe"),
        npsTrack("yell-YELLSORAVIRAWISN20150617T42.mp3",  title: "Bird Chorus"),
        npsTrack("yell-YELLDawnChorus.mp3",               title: "Dawn Chorus"),

        // Geysers
        npsTrack("yell-030106GeyserHillAnemoneGeyserDrainingSonyM100101.mp3", title: "Anemone Geyser Draining"),
        npsTrack("yell-YELLAnemoneGeyser20150323T0201.mp3",      title: "Anemone Geyser (1)"),
        npsTrack("yell-YELLAnemoneGeyser20150323T02msexcerpt01.mp3", title: "Anemone Geyser (2)"),
        npsTrack("yell-090101GeyserHillBeehiveEruptionBinaural0101.mp3", title: "Beehive Geyser Eruption"),
        npsTrack("yell-100101BeehiveMix01Fix101.mp3",            title: "Beehive Geyser (2)"),
        npsTrack("yell-YELLBeehiveGeyser20150322T03ms01.mp3",    title: "Beehive Geyser (3)"),
        npsTrack("yell-CastleGeyser.mp3",                        title: "Castle Geyser"),
        npsTrack("yell-020201BlackSandBasinThermalPoolNearCliffsideGeyserOverlookMKH416-3001011.mp3", title: "Cliff Geyser, Thermal Pool"),
        npsTrack("yell-020202BlackSandBasinSmallVentNearCliffsideGeyserOverlookMKH416-300201.mp3",    title: "Cliff Geyser, Small Vent"),
        npsTrack("yell-CliffGeyser.mp3",                         title: "Cliff Geyser"),
        npsTrack("yell-090102GeyserHillGrandEruptionMKH416-300101.mp3", title: "Grand Geyser Eruption"),
        npsTrack("yell-120101GrandMix0101.mp3",                  title: "Grand Geyser (2)"),
        npsTrack("yell-YELLGrandGeyser20150322T11ms.mp3",        title: "Grand Geyser (3)"),
        npsTrack("yell-OldFaithful11162014.mp3",                 title: "Old Faithful (1)"),
        npsTrack("yell-YELLOldFaithful20150322T13ms.mp3",        title: "Old Faithful (2)"),
        npsTrack("yell-YELLOldFaithful20150322T02ms.mp3",        title: "Old Faithful (3)"),
        npsTrack("yell-00150325YellowstoneOldFaithfulGeyserEruption3Mix3Alt101.mp3", title: "Old Faithful Eruption"),
        npsTrack("yell-SawmillGeyser2.mp3",                      title: "Sawmill Geyser"),
        npsTrack("yell-050402NorrisGeyserBasinVeteranMKH40-300201.mp3", title: "Veteran Geyser (1)"),
        npsTrack("yell-050403NorrisGeyserBasinVeteranVentCloseupMKH416-300201.mp3", title: "Veteran Geyser Vent"),
        npsTrack("yell-VeteranGeyser150313.mp3",                 title: "Veteran Geyser (3)"),
        npsTrack("yell-VixenGeyser150313.mp3",                   title: "Vixen Geyser"),
        npsTrack("yell-YELLPuffnStuffGeyser150313.mp3",          title: "Puff 'n Stuff Geyser"),
        npsTrack("yell-030202GeyserHillScissorSpringsGeyserBinaural0201.mp3", title: "Scissors Springs Geyser (1)"),
        npsTrack("yell-YELLScissorSpringsGeyser150322001D100.mp3", title: "Scissors Springs Geyser (2)"),

        // Thermal features
        npsTrack("yell-YELLArtistPaintPots141124.mp3",           title: "Artist Paint Pots"),
        npsTrack("yell-010102BerylSpringBinaural01011.mp3",       title: "Beryl Spring (1)"),
        npsTrack("yell-YELLBerylSpring20150315T45ms013.mp3",      title: "Beryl Spring (2)"),
        npsTrack("yell-050301NorrisGeyserBasinBlackGrowlerSteamVentBinaural0101.mp3", title: "Black Growler Steam Vent (1)"),
        npsTrack("yell-NorrisBlackGrowler.mp3",                   title: "Black Growler Steam Vent (2)"),
        npsTrack("yell-020102BlackSandBasinBlackSandPoolImplodingBubblesBinaural0101.mp3", title: "Black Sand Pool, Imploding Bubbles"),
        npsTrack("yell-YELLBlackSandPool20150323T11ms01.mp3",     title: "Black Sand Pool (2)"),
        npsTrack("yell-DragonsMouth.mp3",                         title: "Dragon's Mouth Spring"),
        npsTrack("yell-EarSpring.mp3",                            title: "Ear Spring"),
        npsTrack("yell-FountainPaintPot.mp3",                     title: "Fountain Paint Pot"),
        npsTrack("yell-NorrisPorcelainBasinFumarolesSmall.mp3",   title: "Norris Fumaroles (1)"),
        npsTrack("yell-NorrisPorcelainBasinFumerole.mp3",         title: "Norris Fumaroles (2)"),
        npsTrack("yell-050101NorrisGeyserBasinPorcelainBasinOverlookingHurricaneVentBinaural0101.mp3", title: "Hurricane Vent"),
        npsTrack("yell-YellowstoneLakeSings.mp3",                 title: "Singing Lake"),
        npsTrack("yell-020301BlackSandBasinSpouterMainBluePoolBinaural01012.mp3",  title: "Spouter Geyser, Blue Pool (1)"),
        npsTrack("yell-020302BlackSandBasinSpouterMainBluePoolAndSurroundingFeaturesBinaural02011.mp3", title: "Spouter Geyser, Blue Pool (2)"),
        npsTrack("yell-020303BlackSandBasinSpouterRoadsideCulvertBinaural03011.mp3", title: "Spouter Geyser, Culvert"),

        // Wildlife
        npsTrack("yell-YELLEagle140829.mp3",                     title: "Bald Eagle (1)"),
        npsTrack("yell-YELLBAEA20160912T07ms.mp3",               title: "Bald Eagle (2)"),
        npsTrack("yell-YELLBAEA20160914T12ms.mp3",               title: "Bald Eagle (3)"),
        npsTrack("yell-GrizzlyEating010315.mp3",                  title: "Grizzly Bear Eating"),
        npsTrack("yell-YELLgrizzlyA20160624SM3031431.mp3",        title: "Grizzly Bear (1)"),
        npsTrack("yell-YELLgrizzlyB20160624SM3031431.mp3",        title: "Grizzly Bear (2)"),
        npsTrack("yell-YELLGrizzlyBearVocalizations20160520Android1.mp3", title: "Grizzly Bear Vocalizations"),
        npsTrack("yell-YELLgrizzlyC20160626SM303143.mp3",         title: "Grizzly Bear (3)"),
        npsTrack("YELL-BisonRut-JenniferJerrett.mp3",             title: "Bison Rut (1)"),
        npsTrack("yell-YELLMM8K2005914Bison.mp3",                 title: "Bison Rut (2)"),
        npsTrack("yell-YELLMM8K2005918Bison.mp3",                 title: "Bison Rut (3)"),
        npsTrack("yell-YELLBisonEating150313.mp3",                title: "Bison Eating"),
        npsTrack("yell-ChorusFrogs.mp3",                          title: "Boreal Chorus Frogs (1)"),
        npsTrack("yell-20150427T13BorealfrogSACRWISN.mp3",        title: "Boreal Chorus Frogs (2)"),
        npsTrack("yell-Coyotes.mp3",                              title: "Coyotes (1)"),
        npsTrack("yell-YELLCoyotes150315.mp3",                    title: "Coyotes (2)"),
        npsTrack("yell-YELLCoyotes20160505SM31.mp3",              title: "Coyotes (3)"),
        npsTrack("yell-ElkBugle1.mp3",                            title: "Elk Bugle (1)"),
        npsTrack("yell-ElkBugle2.mp3",                            title: "Elk Bugle (2)"),
        npsTrack("yell-YELLMJ23ElkCalf20051116.mp3",              title: "Elk Calf"),
        npsTrack("yell-YELLElkChorus150922T04ms01.mp3",           title: "Elk Chorus"),
        npsTrack("yell-YELLElkBullandCows20151018T012.mp3",       title: "Elk Bull and Cows"),
        npsTrack("yell-YELLLakeElkRut20160912T15ms.mp3",          title: "Lake Elk Rut (1)"),
        npsTrack("yell-YELLLakeElkRut20160913T004ms1.mp3",        title: "Lake Elk Rut (2)"),
        npsTrack("yell-YELLMJ23200837redfox.mp3",                 title: "Red Fox"),
        npsTrack("yell-YELLSGYredsquirrel2004320.mp3",            title: "Red Squirrel"),
        npsTrack("yell-YELLSpadefootToads20150520T14ms.mp3",      title: "Spadefoot Toads"),
        npsTrack("yell-YELLUintagroundsquirrel20160601T01.mp3",   title: "Uinta Ground Squirrel"),
        npsTrack("yell-YELLWolvesDec252013.mp3",                  title: "Wolves, Winter 2013"),
        npsTrack("yell-YELLWolves20160111T20ms2.mp3",             title: "Wolves (2)"),
        npsTrack("yell-YELLWolfvCar20160111T22ms2.mp3",           title: "Wolf vs. Car"),

        // Soundscapes
        npsTrack("yell-030401GeyserHillStreamOffBoardwalkBackgroundGeyserRumblesAndWindBinaural0101.mp3", title: "Geyser Hill Soundscape"),
        npsTrack("yell-030402GeyserHillNearSulphideSpringBirdsBinaural0101.mp3",  title: "Sulphide Spring Birds"),
        npsTrack("yell-040201LowerGeyserBasinWindInTreesBinaural01011.mp3",        title: "Lower Geyser Basin Wind"),
        npsTrack("yell-YELLCabinSoundsWind20160912T032.mp3",      title: "Cabin Sounds, Wind"),
        npsTrack("yell-YELLChopKindling20160913T0011.mp3",         title: "Chopping Kindling"),
        npsTrack("yell-YELLLakeElkRut20160913T004ms.mp3",          title: "Lake Soundscape with Elk"),
        npsTrack("yell-YELLLakeSoundscape20160913T01ms.mp3",       title: "Lake Soundscape (1)"),
        npsTrack("yell-YELLLakeSoundscape20160914T001ms.mp3",      title: "Lake Soundscape (2)"),
        npsTrack("yell-YELLLakeSoundscape20160914T03ms.mp3",       title: "Lake Soundscape (3)"),
        npsTrack("yell-YELLLakeSoundscape20160914T05ms.mp3",       title: "Lake Soundscape (4)"),
        npsTrack("yell-YELLLakeSoundscape20160914T06ms.mp3",       title: "Lake Soundscape (5)"),
        npsTrack("yell-YELLLakeSoundscape20160914T14ms.mp3",       title: "Lake Soundscape (6)"),
        npsTrack("yell-YELLPealeCabinWoodstove20160914T15ms.mp3",  title: "Peale Cabin Woodstove"),
        npsTrack("yell-YELLSplitLogs20160913T002.mp3",             title: "Splitting Logs"),
        npsTrack("yell-YELLhorsebackriders20150616T06.mp3",        title: "Horse-Drawn Wagon"),
        npsTrack("yell-YELLsnowmobile.mp3",                        title: "Snowmobile"),
        npsTrack("yell-Thunderandbirds140704.mp3",                  title: "Thunder and Birds"),
        npsTrack("yell-YELLMapleFire20160814T04ms3.mp3",           title: "Maple Fire (1)"),
        npsTrack("yell-YELLMapleFire20160814T08ms.mp3",            title: "Maple Fire (2)"),
        npsTrack("yell-YELLMapleFire20160814T12ms.mp3",            title: "Maple Fire (3)"),
    ]}
}
