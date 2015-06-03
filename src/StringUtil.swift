import Foundation

struct StringUtil {

  static func underscore(string: String) -> String {
    var output = ""

    for char in string {
      if ("A"..."Z").contains(char) {
        output += "_"
        output += String(char).lowercaseString
      } else {
        output += String(char)
      }
    }
    
    return output
  }

}
