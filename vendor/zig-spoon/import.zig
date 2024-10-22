// This file is part of zig-spoon, a TUI library for the zig language.
//
// Copyright © 2022 Leon Henrik Plickat
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License version 3 as published
// by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

pub const version = "0.1.0";

pub const spells = @import("lib/spells.zig");

pub const Attribute = @import("lib/Attribute.zig");
pub const Term = @import("lib/Term.zig");
pub const inputParser = @import("lib/input.zig").inputParser;
pub const Input = @import("lib/input.zig").Input;
pub const InputContent = @import("lib/input.zig").InputContent;

pub const restrictedPaddingWriter = @import("lib/restricted_padding_writer.zig").restrictedPaddingWriter;
pub const RestrictedPaddingWriter = @import("lib/restricted_padding_writer.zig").RestrictedPaddingWriter;
