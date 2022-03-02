/* === This file is part of Calamares - <http://github.com/calamares> ===
 *
 *   Copyright 2015, Teo Mrnjavac <teo@kde.org>
 *   Copyright 2016, Luca Giambonini <almack@chakralinux.org>
 *
 *   Calamares is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   Calamares is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with Calamares. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0;
import calamares.slideshow 1.0;

/* Tested with slide images of 1800x1200 and 1632x1248 pixels */

Presentation
{
    id: presentation

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            id: pic0
            source: "thanks.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic00
            source: "artix.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic01
            source: "inits.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic02
            source: "tools.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic03
            source: "desktops.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic04
            source: "productivity.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic05
            source: "games.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic06
            source: "browsers.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic07
            source: "office.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic08
            source: "multimedia.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic09
            source: "web.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic10
            source: "theme.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic11
            source: "packages1.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic12
            source: "packages2.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic13
            source: "packages3.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic14
            source: "packages4.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic15
            source: "customise.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }

    Slide {
        Image {
            id: pic16
            source: "rolling.png"
            width: parent.width * 1.12; height: parent.height * 1.5
            fillMode: Image.Stretch
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
        }
    }
}
