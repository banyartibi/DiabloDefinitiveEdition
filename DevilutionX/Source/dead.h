/**
 * @file dead.h
 *
 * Interface of functions for placing dead monsters.
 */
#pragma once

#include <array>
#include <cstdint>

#include "engine.h"
#include "engine/clx_sprite.hpp"
#include "engine/point.hpp"

namespace devilution {

static constexpr unsigned MaxCorpses = 31;

struct Corpse {
	OptionalClxSpriteListOrSheet sprites;
	int frame;
	uint16_t width;
	uint8_t translationPaletteIndex;

	/**
	 * @brief Returns the sprite list for a given direction.
	 *
	 * @param direction One of the 16 directions. Valid range: [0, 15].
	 * @return ClxSpriteList
	 */
	[[nodiscard]] ClxSpriteList spritesForDirection(Direction direction) const
	{
		if (!sprites->isSheet())
			return sprites->list();
		size_t numLists = sprites->sheet().numLists();
		if (numLists == 0)
			return sprites->list();
		size_t safeDir = std::min<size_t>(static_cast<size_t>(direction), numLists - 1);
		return sprites->sheet()[safeDir];
	}
};

extern Corpse Corpses[MaxCorpses];
extern int8_t stonendx;

void InitCorpses();
void AddCorpse(Point tilePosition, int8_t dv, Direction ddir);
void MoveLightsToCorpses();

} // namespace devilution
