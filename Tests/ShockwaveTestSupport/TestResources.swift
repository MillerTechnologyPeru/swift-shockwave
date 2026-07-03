import Foundation

/// Locations of the real Director sample files shared by every test target.
public enum TestResources {
  public static var junkbotMovieURL: URL {
    Bundle.module.url(
      forResource: "junkbot2_13g_asp", withExtension: "dir", subdirectory: "Resources")!
  }

  public static var junkbotShockwaveURL: URL {
    Bundle.module.url(
      forResource: "junkbot2_13g_asp", withExtension: "dcr", subdirectory: "Resources")!
  }
}
