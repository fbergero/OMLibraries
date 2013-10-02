BUILD_DIR=build/
OMC=omc
SVN_DIRS="MSL 3.2.1" "MSL 3.1" "MSL 2.2.2" "MSL 1.6" "Biochem" "NewTables" "Modelica_EmbeddedSystems" "Modelica3D" "ADGenKinetics" "BondGraph" "Buildings" "IndustrialControlSystems" "LinearMPC" "OpenHydraulics" "RealTimeCoordinationLibrary" "PowerFlow" "EEnStorage" "InstantaneousSymmetricalComponents"

all: Makefile.numjobs config.done
	rm -rf $(BUILD_DIR) build
	rm -f *.uses
	$(MAKE) all-work
	@# Could run uses and test at the same time, but this way we get nicer error-messages and a faster error if the uses fail (they are a lot faster than test)
	$(MAKE) uses
	$(MAKE) test
all-work: config.done Makefile.numjobs
	mkdir -p $(BUILD_DIR) svn
	./update-library.py -n `cat Makefile.numjobs` --build-dir $(BUILD_DIR) --omc $(OMC)
	$(MAKE) modelica3d
config.done: Makefile
	which rm > /dev/null
	which svn > /dev/null
	which git > /dev/null
	$(OMC) ++v > /dev/null
	which xargs > /dev/null
	#which xsltproc > /dev/null
	which xpath > /dev/null
	touch config.done
Makefile.numjobs:
	@echo 7 > $@
	@echo "*** Setting number of jobs to 5. 1 makes things too slow and 5 threads. Set $@ if you want to change it ***"
modelica3d:
	@echo Much more work is needed for Modelica3D. For now the native builds are part of the omc packages
	install -m755 -d "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/"
	install -m755 -d "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/modbus"
	install -m755 -d "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/modcount"
	install -m755 -d "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/Modelica3D"
	install -p -m644 "svn/Modelica3D/lib/modbus/src/modelica/modbus/package.mo" "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/modbus/package.mo"
	install -p -m644 "svn/Modelica3D/lib/mod3d/src/modelica/Modelica3D 3.2.1/package.mo" "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/Modelica3D/package.mo"
	install -p -m644 "svn/Modelica3D/lib/modcount/src/modelica/modcount/package.mo" "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/modcount/package.mo"
	install -p -m644 "$(BUILD_DIR)/ModelicaServices 3.2.1/package.mo" "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/package.mo"
	patch "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d/package.mo" -p1 < "ModelicaServices 3.2.1 modelica3d.patch"
	find "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d" -name "*.orig" -exec rm -f "{}" ";"
	echo `cat "$(BUILD_DIR)/ModelicaServices 3.2.1.last_change"`-m3d`svn info --xml "svn/Modelica3D" | xpath -q -e '/info/entry/commit/@revision' | grep -o "[0-9]*"`-om3d`git rev-list HEAD --count "ModelicaServices 3.2.1 modelica3d.patch"` > "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d.last_change"
	# svn log --xml --verbose "svn/Modelica3D" | sed "s,<date>.*</date>,<date>1970-01-01</date>," | sed "s,<author>\(.*\)</author>,<author>none</author><author-svn>\1</author-svn>," | xsltproc svn2cl.xsl - > "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d.changes"
	cp "$(BUILD_DIR)/ModelicaServices 3.2.1.license" "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d.license"
	echo "deb:libmodelica3d" >> "$(BUILD_DIR)/ModelicaServices 3.2.1 modelica3d.uses"

test: config.done Makefile.numjobs
	rm -f error.log test-valid.*.mos
	find $(BUILD_DIR)/*.mo $(BUILD_DIR)/*/package.mo -print0 | xargs -0 -n 1 -P `cat Makefile.numjobs` sh -c './test-valid.sh "$(OMC)" "$(BUILD_DIR)" "$$1"' sh
	test ! -f error.log || cat error.log
	test ! -f error.log
	rm -f error.log test-valid.*.mos
uses: config.done Makefile.numjobs
	find $(BUILD_DIR)/*.uses -print0 | xargs -0 -n 1 -P `cat Makefile.numjobs` sh -c './check-uses.sh "$(BUILD_DIR)" "$$1"' sh
clean:
	rm -f *.rev *.uses  test-valid.*.mos config.done
	rm -rf build debian-build $(SVN_DIRS)

check-latest: config.done Makefile.numjobs
	@echo "Looking for more recent versions of packages"
	./update-library.py -n `cat Makefile.numjobs` --check-latest
add-missing: config.done Makefile.numjobs
	@echo "Adding missing github repositories using trunk / latest revision"
	./update-library.py -n `cat Makefile.numjobs` --add-missing

# .remote/control-files: Directory where the list of packages should be stored. Used by a shell-script + apt-ftparchive
# .remote/pool: Directory where the deb-packages and sources should be stored
debian: config.done Makefile.numjobs .remote/control-files .remote/pool
	rm -rf debian-build
	mkdir -p debian-build
	scp "`cat .remote/control-files`/nightly-library-files" .remote/nightly-library-files
	scp "`cat .remote/control-files`/nightly-library-sources" .remote/nightly-library-sources
	find $(BUILD_DIR)/*.ok -print0 | xargs -0 -n 1 -P `cat Makefile.numjobs` sh -c './debian-build.sh "$$1"' sh
	./check-debian.sh
	diff -u .remote/nightly-library-files nightly-library-files || true
	diff -u .remote/nightly-library-sources nightly-library-sources || true
upload: config.done .remote/control-files .remote/pool .remote/release-command
	diff -u .remote/nightly-library-files nightly-library-files || (! stat -t debian-build/*.deb >/dev/null 2>&1) || scp debian-build/*.deb debian-build/*.tar.gz debian-build/*.dsc "`cat .remote/pool`"
	scp nightly-library-files nightly-library-sources "`cat .remote/control-files`"
	`cat .remote/release-command`
	scp "`cat .remote/control-files`/nightly-library-files" .remote/nightly-library-files
	scp "`cat .remote/control-files`/nightly-library-sources" .remote/nightly-library-sources
	./check-debian.sh
