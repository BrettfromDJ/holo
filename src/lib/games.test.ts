import { describe, expect, it } from "vitest";
import { compactCount, orderGames, shortGameName } from "./games";

describe("games", () => {
  it("shortens names like the app", () => {
    expect(shortGameName("Magic: The Gathering")).toBe("Magic");
    expect(shortGameName("YuGiOh")).toBe("Yu-Gi-Oh!");
    expect(shortGameName("Pokemon Japan")).toBe("Pokémon Japan");
    expect(shortGameName("Disney Lorcana")).toBe("Lorcana");
    expect(shortGameName("Some Trading Card Game")).toBe("Some");
  });
  it("orders games the owner's way", () => {
    const games = [
      { name: "Pokemon Japan", sets: 500 },
      { name: "YuGiOh", sets: 400 },
      { name: "Magic: The Gathering", sets: 900 },
      { name: "Digimon Card Game", sets: 50 },
      { name: "Pokemon", sets: 200 },
      { name: "One Piece Card Game", sets: 30 },
      { name: "Disney Lorcana", sets: 10 },
    ];
    expect(orderGames(games).map((g) => shortGameName(g.name))).toEqual(["Pokémon", "One Piece", "Lorcana", "Magic", "Yu-Gi-Oh!", "Digimon", "Pokémon Japan"]);
  });
  it("compacts counts", () => {
    expect(compactCount(240)).toBe("240");
    expect(compactCount(33_412)).toBe("33K");
    expect(compactCount(1234)).toBe("1.2K");
  });
});
