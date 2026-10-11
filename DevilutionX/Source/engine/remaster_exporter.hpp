#pragma once

#include <cstdint>
#include <string>

namespace devilution {

void RunRemasterAssetPipeline();
void RemasterWarriorClass();
void RemasterDroppedItems();
void RemasterAllMonsters();
void RemasterTowners();
void RemasterObjects();
void RemasterMissiles();
void RemasterAllCoreAssets();
void RemasterSingleFamily(const std::string &familyPrefix, uint16_t widthHint = 128, const char *pal = "levels\\l1data\\l1_1.pal");

} // namespace devilution
