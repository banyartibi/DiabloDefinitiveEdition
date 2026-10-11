#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <filesystem>
#include "libmpq/mpq.h"

namespace fs = std::filesystem;

int main(int argc, char **argv) {
    const char *mpq_path = "/home/biti/.local/share/diasurgical/devilution/DIABDAT.MPQ";
    if (argc > 1) mpq_path = argv[1];

    mpq_archive_s *archive = nullptr;
    int32_t ret = libmpq__archive_open(&archive, mpq_path, -1);
    if (ret != 0) {
        std::cerr << "Failed to open MPQ archive: " << mpq_path << " (error: " << libmpq__strerror(ret) << ")" << std::endl;
        return 1;
    }
    std::cout << "Opened MPQ: " << mpq_path << std::endl;

    std::vector<std::string> files_to_extract = {
        "levels\\l1data\\l1.cel",
        "levels\\l1data\\l1.min",
        "levels\\l1data\\l1.til",
        "levels\\l1data\\l1_1.pal",
        "levels\\l2data\\l2.cel",
        "levels\\l2data\\l2.min",
        "levels\\l2data\\l2.til",
        "levels\\l2data\\l2_1.pal",
        "levels\\l3data\\l3.cel",
        "levels\\l3data\\l3.min",
        "levels\\l3data\\l3.til",
        "levels\\l3data\\l3_1.pal",
        "levels\\l4data\\l4.cel",
        "levels\\l4data\\l4.min",
        "levels\\l4data\\l4.til",
        "levels\\l4data\\l4_1.pal",
        "levels\\towndata\\town.cel",
        "levels\\towndata\\town.min",
        "levels\\towndata\\town.til",
        "levels\\towndata\\town.pal",
        "levels\\towndata\\sector1s.dun",
        "levels\\towndata\\sector2s.dun",
        "levels\\towndata\\sector3s.dun",
        "levels\\towndata\\sector4s.dun"
    };

    fs::path base_out = "/home/biti/antigravity/magical-bell/extracted_assets";

    for (const auto &rel_path : files_to_extract) {
        uint32_t file_num = 0;
        ret = libmpq__file_number(archive, rel_path.c_str(), &file_num);
        if (ret != 0) {
            std::cerr << "File not found in MPQ: " << rel_path << std::endl;
            continue;
        }

        libmpq__off_t unpacked_sz = 0;
        ret = libmpq__file_size_unpacked(archive, file_num, &unpacked_sz);
        if (ret != 0) {
            std::cerr << "Could not get size for: " << rel_path << std::endl;
            continue;
        }

        std::vector<uint8_t> buffer(unpacked_sz);
        libmpq__off_t transferred = 0;
        ret = libmpq__file_read_with_filename(archive, file_num, rel_path.c_str(), buffer.data(), unpacked_sz, &transferred);
        if (ret != 0) {
            std::cerr << "Failed to read file: " << rel_path << " (error: " << libmpq__strerror(ret) << ")" << std::endl;
            continue;
        }

        std::string unix_path = rel_path;
        for (char &c : unix_path) {
            if (c == '\\') c = '/';
        }
        fs::path dest = base_out / unix_path;
        fs::create_directories(dest.parent_path());
        std::ofstream ofs(dest, std::ios::binary);
        ofs.write(reinterpret_cast<const char*>(buffer.data()), transferred);
        ofs.close();
        std::cout << "[Extracted] " << rel_path << " (" << transferred << " bytes) -> " << dest << std::endl;
    }

    libmpq__archive_close(archive);
    std::cout << "All requested level files extracted successfully!" << std::endl;
    return 0;
}
